#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const filename = fileURLToPath(import.meta.url);
const readConfig = name => JSON.parse(fs.readFileSync(new URL(`../configs/brave/${name}`, import.meta.url), 'utf8'));
const appearance = readConfig('appearance.json');
// Dotted preference paths -> values, captured from a hand-configured profile
// (the README lists what they are): Leo, Rewards, Wallet and News UI off,
// wide address bar with full URLs, Google as the search engine in normal and
// private windows. Arrays and objects replace the stored value whole.
export const PREFERENCES = readConfig('preferences.json');
// The same for `Local State` (browser-wide, not per profile): P3A and
// metrics reporting off.
export const LOCAL_STATE = readConfig('local-state.json');

const isObject = value => typeof value === 'object' && value !== null && !Array.isArray(value);

// A captured object is merged into the stored one key by key (so the search
// engine dictionaries keep the ids and timestamps the browser assigned);
// arrays and scalars replace the stored value.
function merged(stored, captured) {
    if (!isObject(captured)) return structuredClone(captured);
    const result = isObject(stored) ? structuredClone(stored) : {};
    for (const [key, value] of Object.entries(captured)) result[key] = merged(result[key], value);
    return result;
}

// Set each "a.b.c" path on a deep copy, creating objects on the way; every
// other key the browser wrote is kept, so private profile data is untouched.
export function withSettings(current, settings) {
    const next = structuredClone(current);
    for (const [dotted, value] of Object.entries(settings)) {
        const keys = dotted.split('.');
        let node = next;
        for (const key of keys.slice(0, -1)) {
            if (!isObject(node[key])) node[key] = {};
            node = node[key];
        }
        node[keys.at(-1)] = merged(node[keys.at(-1)], value);
    }
    return next;
}

// Preserve private profile data and site-specific zoom; never track Preferences.
export function appearancePreferences(current) {
    const next = withSettings(current, PREFERENCES);
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
    const result = text.replace(/^Exec=(\/[^\s]*brave-browser(?:-stable)?)(.*)$/gm, (_, binary, args) => {
        count++;
        const rest = args.replace(/\s+--force-device-scale-factor=\S+/g, '');
        return `Exec=${binary} --force-device-scale-factor=${appearance.interfaceScale}${rest}`;
    });
    if (!count) throw new Error('No supported Brave Exec entries found.');
    return result;
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

export function configureBrave({
    home = process.env.HOME,
    configHome = process.env.XDG_CONFIG_HOME || path.join(home, '.config'),
    dataHome = process.env.XDG_DATA_HOME || path.join(home, '.local/share'),
    desktop = '/usr/share/applications/brave-browser.desktop',
    run = spawnSync, log = console.log, warn = console.warn,
} = {}) {
    if (!fs.existsSync(desktop)) {
        log('Brave is not installed — skipping appearance setup.');
        return;
    }
    replaceWithBackup(path.join(dataHome, 'applications/brave-browser.desktop'), scaledLauncher(fs.readFileSync(desktop, 'utf8')));
    log('Brave launcher: 120% interface scaling.');

    const running = run('pgrep', ['-x', 'brave'], { encoding: 'utf8' });
    if (running.status !== 1) {
        warn('Close Brave and rerun setup.sh --brave-only to apply page zoom and font sizes.');
        return;
    }
    const root = path.join(configHome, 'BraveSoftware', 'Brave-Browser');
    const stateFile = path.join(root, 'Local State');
    const state = fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, 'utf8')) : {};
    const profile = state.profile?.last_used || 'Default';
    if (path.basename(profile) !== profile || profile === '.' || profile === '..') throw new Error('Invalid Brave profile directory.');
    const preferences = path.join(root, profile, 'Preferences');
    if (!fs.existsSync(preferences)) {
        warn('Open Brave once, close it, then rerun setup.sh --brave-only to configure the profile.');
        return;
    }
    const current = JSON.parse(fs.readFileSync(preferences, 'utf8'));
    const next = appearancePreferences(current);
    if (JSON.stringify(current) !== JSON.stringify(next)) replaceWithBackup(preferences, JSON.stringify(next));
    log('Brave profile: 115% page zoom, 17px standard font, 14px monospace font, Google search, Leo/Rewards/Wallet/News UI off.');
    const nextState = withSettings(state, LOCAL_STATE);
    if (JSON.stringify(state) !== JSON.stringify(nextState)) replaceWithBackup(stateFile, JSON.stringify(nextState));
    log('Brave: P3A and metrics reporting off.');
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        if (process.argv.length !== 2) throw new Error('Usage: brave-profile.mjs');
        configureBrave();
    } catch (error) {
        console.error(`brave-profile: ${error.message}`);
        process.exitCode = 1;
    }
}
