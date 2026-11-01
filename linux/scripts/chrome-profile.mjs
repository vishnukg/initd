#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const filename = fileURLToPath(import.meta.url);
const appearance = JSON.parse(fs.readFileSync(new URL('../configs/chrome/appearance.json', import.meta.url), 'utf8'));

// Preserve private profile data and site-specific zoom; never track Preferences.
export function appearancePreferences(current) {
    const next = structuredClone(current);
    const web = (next.webkit ??= {}).webprefs ??= {};
    web.default_font_size = appearance.fontSize;
    web.default_fixed_font_size = appearance.monospaceFontSize;
    const zoom = (next.partition ??= {}).default_zoom_level ??= {};
    // Chromium stores log-base-1.2 zoom levels; x is the default partition.
    zoom.x = Math.log(appearance.pageZoom) / Math.log(1.2);
    return next;
}

export function scaledLauncher(text) {
    let count = 0;
    const result = text.replace(/^Exec=(\/[^\s]*google-chrome(?:-stable)?)(.*)$/gm, (_, binary, args) => {
        count++;
        const rest = args.replace(/\s+--force-device-scale-factor=\S+/g, '');
        return `Exec=${binary} --force-device-scale-factor=${appearance.interfaceScale}${rest}`;
    });
    if (!count) throw new Error('No supported Chrome Exec entries found.');
    return result;
}

// The packaged desktop ID: com.google.Chrome.desktop ships alongside it but is
// NoDisplay, and the scaled launcher above shadows this ID, so links opened
// through xdg-open get the 120% launcher too.
export const BROWSER = 'google-chrome.desktop';

// xdg-settings writes ~/.config/mimeapps.list (text/html plus the http/https
// handlers), which both Hyprland and GNOME read. Checked first so a re-run is a
// no-op; a failure warns rather than aborting the rest of the Chrome setup.
export function setDefaultBrowser({ run = spawnSync, log = console.log, warn = console.warn } = {}) {
    const current = run('xdg-settings', ['get', 'default-web-browser'], { encoding: 'utf8' });
    if (current.status === 0 && current.stdout?.trim() === BROWSER) {
        log('Chrome is already the default browser.');
        return;
    }
    const set = run('xdg-settings', ['set', 'default-web-browser', BROWSER], { encoding: 'utf8' });
    if (set.status === 0) log('Chrome set as the default browser.');
    else warn(`Could not make Chrome the default browser: ${set.stderr?.trim() || set.error?.message || `xdg-settings exited ${set.status}`}`);
}

function replaceWithBackup(file, contents) {
    if (fs.existsSync(file) && fs.readFileSync(file, 'utf8') === contents) return;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const previous = fs.existsSync(file) ? fs.statSync(file) : null;
    if (previous) fs.copyFileSync(file, `${file}.initd-backup-${Date.now()}`, fs.constants.COPYFILE_EXCL);
    const temporary = `${file}.initd-${process.pid}.tmp`;
    try {
        fs.writeFileSync(temporary, contents, { flag: 'wx', mode: previous ? previous.mode & 0o777 : 0o600 });
        fs.renameSync(temporary, file);
    } finally {
        if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
    }
}

export function configureChrome({
    home = process.env.HOME,
    configHome = process.env.XDG_CONFIG_HOME || path.join(home, '.config'),
    dataHome = process.env.XDG_DATA_HOME || path.join(home, '.local/share'),
    desktop = '/usr/share/applications/google-chrome.desktop',
    run = spawnSync, log = console.log, warn = console.warn,
} = {}) {
    if (!fs.existsSync(desktop)) {
        log('Chrome is not installed — skipping appearance setup.');
        return;
    }
    replaceWithBackup(path.join(dataHome, 'applications/google-chrome.desktop'), scaledLauncher(fs.readFileSync(desktop, 'utf8')));
    log('Chrome launcher: 120% interface scaling.');
    setDefaultBrowser({ run, log, warn });

    const running = run('pgrep', ['-x', 'chrome'], { encoding: 'utf8' });
    if (running.status !== 1) {
        warn('Close Chrome and rerun setup.sh --chrome-only to apply page zoom and font sizes.');
        return;
    }
    const root = path.join(configHome, 'google-chrome');
    const stateFile = path.join(root, 'Local State');
    const state = fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, 'utf8')) : {};
    const profile = state.profile?.last_used || 'Default';
    if (path.basename(profile) !== profile || profile === '.' || profile === '..') throw new Error('Invalid Chrome profile directory.');
    const preferences = path.join(root, profile, 'Preferences');
    if (!fs.existsSync(preferences)) {
        warn('Open Chrome once, close it, then rerun setup.sh --chrome-only to configure the profile.');
        return;
    }
    const current = JSON.parse(fs.readFileSync(preferences, 'utf8'));
    const next = appearancePreferences(current);
    if (JSON.stringify(current) !== JSON.stringify(next)) replaceWithBackup(preferences, JSON.stringify(next));
    log('Chrome profile: 115% page zoom, 17px standard font, 14px monospace font.');
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        if (process.argv.length !== 2) throw new Error('Usage: chrome-profile.mjs');
        configureChrome();
    } catch (error) {
        console.error(`chrome-profile: ${error.message}`);
        process.exitCode = 1;
    }
}
