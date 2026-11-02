#!/usr/bin/env node
// Wallpaper-driven colour theme (Material You via matugen), applied to the
// whole desktop from one palette:
//
//   ~/.local/state/initd/theme.json    Quickshell bar, panels, banners (Theme.qml, live)
//   ~/.local/state/initd/rofi.rasi     the launcher (imported by rofi/config.rasi)
//   ~/.local/state/initd/hyprlock.conf the lock screen (sourced by hyprlock.conf)
//   ~/.config/gtk-3.0/gtk.css          GTK3 apps' accent (gitignored; next launch)
//   gsettings accent-color             GTK4/libadwaita apps' accent (live)
//
// Commands:
//   apply <image>  extract a dark scheme from <image> with matugen and write all of it
//   ensure         write the default palette for anything missing (every login, setup.sh)
//   defaults       write the default (blue) palette over everything and set GNOME's accent
//
// A wallpaper change (wallpaper.mjs) writes the defaults, not a matugen scheme:
// the desktop is blue whatever the image.
//
// Stability rules: every file is written atomically (temp + rename), so a
// reader never sees half a file; if matugen is missing or fails, `apply`
// changes nothing and exits non-zero, leaving the current theme in place.
// Status colours (good/warn/bad) never follow the wallpaper -- in this
// desktop colour means state.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// Same roles and values as THEME_DEFAULTS in the bar's bar-logic.mjs, plus the
// solid surface the launcher and lock screen use.
export const DEFAULT_THEME = {
    accent: '#8fb7e8',
    onAccent: '#0b0c10',
    text: '#e8eaf0',
    textMuted: '#aeb4c3',
    textDim: '#656a78',
    textDisabled: '#52566a',
    surface: '#14161d',
    bar: '#b30b0c10',
    menu: '#f20d0e12',
    good: '#8fd6b8',
    warn: '#e8b87a',
    bad: '#e0788a',
};

const HEX = /^#[0-9a-f]{6}$/i;

// matugen's JSON has changed shape across releases; accept each: a role may
// map to "#hex", { dark: "#hex" }, { dark: { color: "#hex" } } or the older
// { colors: { dark: { role: "#hex" } } }. Returns { role: "#hex" } for the
// dark scheme, snake_case role names as matugen spells them.
export function parseMatugen(text) {
    const parsed = JSON.parse(text);
    const colors = parsed && parsed.colors;
    if (!colors || typeof colors !== 'object') throw new Error('matugen output has no colors');
    const source = colors.dark && typeof colors.dark === 'object' && !HEX.test(String(colors.dark.color ?? ''))
        && Object.values(colors.dark).some((v) => typeof v === 'string')
        ? colors.dark : colors;
    const pick = (value) => {
        if (typeof value === 'string') return value;
        if (value && typeof value === 'object') {
            const dark = value.dark ?? value.default ?? value;
            if (typeof dark === 'string') return dark;
            if (dark && typeof dark === 'object') return dark.color ?? dark.hex;
        }
        return undefined;
    };
    const scheme = {};
    for (const [role, value] of Object.entries(source)) {
        const hex = pick(value);
        if (typeof hex === 'string' && HEX.test(hex)) scheme[role] = hex.toLowerCase();
    }
    if (!scheme.primary || !scheme.surface) throw new Error('matugen output lacks primary/surface');
    return scheme;
}

// Material roles -> the desktop's roles. The bar and menus keep their
// translucency (70% / 95%) over the wallpaper-tinted surface.
export function themeFromScheme(scheme) {
    const take = (role, fallback) => (scheme[role] && HEX.test(scheme[role]) ? scheme[role] : fallback);
    const surface = take('surface_container_low', take('surface', DEFAULT_THEME.surface));
    const deep = take('surface_container_lowest', take('surface', DEFAULT_THEME.surface));
    return {
        accent: take('primary', DEFAULT_THEME.accent),
        onAccent: take('on_primary', DEFAULT_THEME.onAccent),
        text: take('on_surface', DEFAULT_THEME.text),
        textMuted: take('on_surface_variant', DEFAULT_THEME.textMuted),
        textDim: take('outline', DEFAULT_THEME.textDim),
        textDisabled: take('outline_variant', DEFAULT_THEME.textDisabled),
        surface,
        bar: '#b3' + deep.slice(1),
        menu: '#f2' + surface.slice(1),
        good: DEFAULT_THEME.good,
        warn: DEFAULT_THEME.warn,
        bad: DEFAULT_THEME.bad,
    };
}

// GNOME's named accents (org.gnome.desktop.interface accent-color), at the hues
// of libadwaita's own accent colours (yellow is #c88800, orange #ed5b00, ...);
// low-chroma colours read as slate.
const ACCENT_HUES = [
    ['red', 353], ['orange', 23], ['yellow', 41], ['green', 131],
    ['teal', 189], ['blue', 213], ['purple', 285], ['pink', 331],
];

export function nearestAccent(hex) {
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
    const max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
    const lightness = (max + min) / 2;
    const saturation = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lightness - 1));
    if (saturation < 0.18) return 'slate';
    let hue = max === r ? ((g - b) / delta) % 6 : max === g ? (b - r) / delta + 2 : (r - g) / delta + 4;
    hue = (hue * 60 + 360) % 360;
    let best = 'blue', distance = 361;
    for (const [name, h] of ACCENT_HUES) {
        const d = Math.min(Math.abs(hue - h), 360 - Math.abs(hue - h));
        if (d < distance) [best, distance] = [name, d];
    }
    return best;
}

// hyprlang colours are rgba(rrggbbaa).
const rgba = (hex, alpha = 'ff') => `rgba(${hex.slice(1, 7)}${alpha})`;

export function renderThemeJson(theme, wallpaper = '') {
    return JSON.stringify({ wallpaper, colors: theme }, null, 2) + '\n';
}

export function renderRofi(theme) {
    return `/* Generated by linux/scripts/theme.mjs -- do not edit. */
* {
    accent:     ${theme.accent};
    on-accent:  ${theme.onAccent};
    surface:    ${theme.surface}e0;
    text:       ${theme.text};
    text-muted: ${theme.textMuted};
    text-dim:   ${theme.textDim};
    urgent:     ${theme.bad};
}
`;
}

export function renderHyprlock(theme) {
    return `# Generated by linux/scripts/theme.mjs -- do not edit.
$accent = ${rgba(theme.accent)}
$on_accent = ${rgba(theme.onAccent)}
$text = ${rgba(theme.text)}
$text_muted = ${rgba(theme.textMuted)}
$surface = ${rgba(theme.surface, 'cc')}
$bad = ${rgba(theme.bad)}
`;
}

export function renderGtk3(theme) {
    return `/* Generated by linux/scripts/theme.mjs -- do not edit. adw-gtk3 reads
   these at app launch, so open GTK3 windows keep their old accent until
   restarted. */
@define-color accent_color ${theme.accent};
@define-color accent_bg_color ${theme.accent};
@define-color accent_fg_color ${theme.onAccent};
`;
}

export function outputs(home = os.homedir()) {
    const state = path.join(home, '.local/state/initd');
    return {
        json: path.join(state, 'theme.json'),
        rofi: path.join(state, 'rofi.rasi'),
        hyprlock: path.join(state, 'hyprlock.conf'),
        gtk3: path.join(home, '.config/gtk-3.0/gtk.css'),
    };
}

export function writeAtomic(file, text) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(temp, text);
    fs.renameSync(temp, file);
}

export function writeTheme(theme, { home = os.homedir(), wallpaper = '', only = null } = {}) {
    const files = outputs(home);
    const contents = {
        json: renderThemeJson(theme, wallpaper),
        rofi: renderRofi(theme),
        hyprlock: renderHyprlock(theme),
        gtk3: renderGtk3(theme),
    };
    const written = [];
    for (const [key, file] of Object.entries(files)) {
        if (only && !only.includes(key)) continue;
        writeAtomic(file, contents[key]);
        written.push(file);
    }
    return written;
}

// Writes the defaults only for files that do not exist yet.
export function ensureTheme({ home = os.homedir() } = {}) {
    const files = outputs(home);
    const missing = Object.keys(files).filter((key) => !fs.existsSync(files[key]));
    return missing.length ? writeTheme(DEFAULT_THEME, { home, only: missing }) : [];
}

export function extractScheme(image, run = execFileSync) {
    const output = run('matugen', ['image', image, '--mode', 'dark', '--json', 'hex', '--dry-run'], {
        encoding: 'utf8', timeout: 30000, maxBuffer: 16 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'],
    });
    // matugen may print log lines before the JSON object.
    const start = output.indexOf('{');
    if (start < 0) throw new Error('matugen printed no JSON');
    return parseMatugen(output.slice(start));
}

export function applyTheme(image, { home = os.homedir(), run = execFileSync, setAccent = true } = {}) {
    if (!fs.existsSync(image)) throw new Error(`no such image: ${image}`);
    const theme = themeFromScheme(extractScheme(image, run));
    writeTheme(theme, { home, wallpaper: image });
    if (setAccent) {
        try {
            run('gsettings', ['set', 'org.gnome.desktop.interface', 'accent-color', nearestAccent(theme.accent)],
                { stdio: 'ignore', timeout: 5000 });
        } catch {
            // No gsettings (or no session bus): GTK4 apps keep their accent.
        }
    }
    return theme;
}

// The fixed blue palette, recorded against the current wallpaper. This is what
// a wallpaper change writes: the desktop stays blue whatever the image (a
// matugen scheme from a moon photo came out yellow). `apply <image>` is still
// there to try a wallpaper-derived scheme by hand.
export function applyDefaultTheme(wallpaper = '', { home = os.homedir(), run = execFileSync, setAccent = true } = {}) {
    writeTheme(DEFAULT_THEME, { home, wallpaper });
    if (setAccent) {
        try {
            run('gsettings', ['set', 'org.gnome.desktop.interface', 'accent-color', nearestAccent(DEFAULT_THEME.accent)],
                { stdio: 'ignore', timeout: 5000 });
        } catch {
            // No gsettings (or no session bus): GTK4 apps keep their accent.
        }
    }
    return DEFAULT_THEME;
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const [command, image] = process.argv.slice(2);
    try {
        if (command === 'apply' && image) {
            const theme = applyTheme(path.resolve(image));
            console.log(`theme: applied from ${image} (accent ${theme.accent})`);
        } else if (command === 'ensure') {
            const written = ensureTheme();
            if (written.length) console.log(`theme: wrote defaults for ${written.length} missing file(s)`);
        } else if (command === 'defaults') {
            applyDefaultTheme();
            console.log('theme: defaults written');
        } else {
            throw new Error('usage: theme.mjs apply <image> | ensure | defaults');
        }
    } catch (error) {
        console.error(`theme: ${error.message}`);
        process.exitCode = 1;
    }
}
