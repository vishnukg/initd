#!/usr/bin/env node
// Make Firefox the default browser, discover/init its profile, link user.js
// (text size, compact density) and chrome/userChrome.css (no window buttons),
// and set the default page zoom. That is all that is managed in the profile:
// theme, fonts and every other pref stay Firefox's own defaults.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { defaultBackupRoot, installLink, pathStat } from '../../shared/lib/fs.mjs';

const usage = 'Usage: firefox-profile.mjs setup | path <profiles.ini> | zoom <content-prefs.sqlite>';
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

// profiles.ini is flat INI: [Section] headers plus key=value lines. Parsed here
// rather than with a library because this repo has no node_modules. Keys are
// lowercased, which is what Python's configparser did before this - so a Firefox
// that writes `default=` rather than `Default=` keeps matching.
function sections(text) {
    const found = [];
    let current = null;
    for (const raw of text.split(/\r?\n/)) {
        const line = raw.trim();
        if (!line || line.startsWith('#') || line.startsWith(';')) continue;
        const header = line.match(/^\[(.*)\]$/);
        if (header) {
            current = { name: header[1], keys: new Map() };
            found.push(current);
            continue;
        }
        const split = line.indexOf('=');
        if (!current || split === -1) continue;
        current.keys.set(line.slice(0, split).trim().toLowerCase(), line.slice(split + 1).trim());
    }
    return found;
}

// Firefox 67+ tracks the active profile per-install in an [InstallXXXX] section
// whose Default= is the profile path directly. That takes priority over the
// legacy per-profile Default=1 flag, because Firefox stops updating the legacy
// flag once an [Install...] section exists - reading it first picks the profile
// the browser actually opens.
//
// Returned exactly as recorded, absolute or relative: the caller resolves a
// relative path against the directory profiles.ini came from.
export function profilePath(text) {
    const all = sections(text);
    const install = all.find(section => section.name.startsWith('Install') && section.keys.get('default'));
    if (install) return install.keys.get('default');
    const legacy = all.find(section => section.keys.get('default') === '1' && section.keys.get('path'));
    return legacy?.keys.get('path') || null;
}

// Fedora's packaged desktop ID. Firefox is the default browser; Brave stays
// installed alongside it.
export const BROWSER = 'org.mozilla.firefox.desktop';

// xdg-settings writes ~/.config/mimeapps.list (text/html plus the http/https
// handlers), which both Hyprland and GNOME read. Checked first so a re-run is a
// no-op; skipped while Firefox is not installed, and a failure only warns.
export function setDefaultBrowser({
    desktop = path.join('/usr/share/applications', BROWSER), run = spawnSync, log = console.log, warn = console.warn,
} = {}) {
    if (!pathStat(desktop)?.isFile()) return;
    const current = run('xdg-settings', ['get', 'default-web-browser'], { encoding: 'utf8' });
    if (current.status === 0 && current.stdout?.trim() === BROWSER) {
        log('Firefox is already the default browser.');
        return;
    }
    const set = run('xdg-settings', ['set', 'default-web-browser', BROWSER], { encoding: 'utf8' });
    if (set.status === 0) log('Firefox set as the default browser.');
    else warn(`Could not make Firefox the default browser: ${set.stderr?.trim() || set.error?.message || `xdg-settings exited ${set.status}`}`);
}

const SETTING = 'browser.content.full-zoom';

// Firefox's own Zoom UI reads per-site full-zoom levels from content-prefs.sqlite
// rather than from any user.js pref, and a groupID of NULL is the global default
// - the level applied to every site without its own saved zoom. Per-site rows
// are left untouched.
export function setDefaultZoom(file, { zoom = 1.33, now = Date.now() } = {}) {
    // Milliseconds here; the Python this replaced passed sqlite3 2 whole seconds.
    const db = new DatabaseSync(file, { timeout: 2000 });
    try {
        // One transaction, so a reader never sees the window where the old
        // default is gone and the new one is not yet written.
        db.exec('begin immediate');
        const existing = db.prepare('select id from settings where name = ? order by id limit 1').get(SETTING);
        const setting = Number(existing?.id
            ?? db.prepare('insert into settings (name) values (?)').run(SETTING).lastInsertRowid);
        // Deleted and re-inserted rather than updated, so a stale duplicate row
        // cannot win on id order.
        db.prepare('delete from prefs where groupID is null and settingID = ?').run(setting);
        db.prepare('insert into prefs (groupID, settingID, value, timestamp) values (NULL, ?, ?, ?)')
            // ContentPrefService2 stores seconds, unlike Places' microseconds.
            .run(setting, zoom, now / 1000);
        db.exec('commit');
    } finally {
        db.close();
    }
}

export function findProfileDirectory({
    home = process.env.HOME, configHome = process.env.XDG_CONFIG_HOME || path.join(home, '.config'),
    run = spawnSync, warn = console.warn,
} = {}) {
    const roots = [path.join(home, '.mozilla/firefox'), path.join(configHome, 'mozilla/firefox')];
    const findRoot = () => roots.find(root => pathStat(path.join(root, 'profiles.ini'))?.isFile());
    let root = findRoot();
    if (!root) {
        // A headless first launch, not --CreateProfile: Firefox does not adopt a
        // profile made that way (it records no install default), so the next
        // real launch made its own "default-release-1" and everything linked
        // here went to a profile nothing used. --screenshot exits by itself
        // (~1 s) after the launch has written the [Install...] default.
        const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-firefox-'));
        let result;
        try {
            result = run('firefox', ['--headless', '--screenshot', path.join(scratch, 'first-run.png'), 'about:blank'], {
                stdio: 'ignore', timeout: 30000, killSignal: 'SIGKILL',
            });
        } finally {
            fs.rmSync(scratch, { recursive: true, force: true });
        }
        if (result.error?.code === 'ENOENT') return null;
        if (result.error || result.status !== 0) {
            warn('!! Firefox could not initialize a profile — retry on the next setup run.');
            return null;
        }
        root = findRoot();
    }
    if (!root) return null;
    const profile = profilePath(fs.readFileSync(path.join(root, 'profiles.ini'), 'utf8'));
    return profile ? path.resolve(root, profile) : null;
}

export function configureFirefox({
    root = repo, home = process.env.HOME, configHome = process.env.XDG_CONFIG_HOME || path.join(home, '.config'),
    backupRoot = defaultBackupRoot(home), run = spawnSync, log = console.log, warn = console.warn,
} = {}) {
    const profile = findProfileDirectory({ home, configHome, run, warn });
    if (!profile) {
        log('==> No Firefox profile present — skipping.');
        return null;
    }
    for (const relative of ['user.js', 'chrome/userChrome.css']) {
        installLink(path.join(profile, relative), path.join(root, 'linux/configs/firefox', relative), { home, backupRoot, log });
    }
    // Cosmetic zoom failures must not undo the link or abort system setup.
    const running = run('pgrep', ['-x', 'firefox'], { stdio: 'ignore', timeout: 3000, killSignal: 'SIGKILL' });
    if (running.error || ![0, 1].includes(running.status)) {
        warn('!! Cannot determine whether Firefox is running — leaving default zoom unchanged.');
    } else if (running.status === 0) {
        warn('!! Firefox is running — close it and rerun setup to set 133% zoom.');
    } else {
        const database = path.join(profile, 'content-prefs.sqlite');
        if (!pathStat(database)?.isFile()) {
            warn('!! Firefox preferences are not initialized — open Firefox once, close it, and rerun setup.');
        } else {
            try {
                setDefaultZoom(database);
                log('OK Set Firefox default zoom to 133%.');
            } catch (error) {
                warn(`!! Could not update Firefox zoom: ${error.message}`);
            }
        }
    }
    return profile;
}

function main([verb, file, ...extra]) {
    if (verb === 'setup' && !file) {
        setDefaultBrowser();
        return configureFirefox();
    }
    if (!file || extra.length || !['path', 'zoom'].includes(verb)) throw new Error(usage);
    if (verb === 'path') {
        const found = profilePath(fs.readFileSync(file, 'utf8'));
        // No active profile is a normal outcome, not an error: the caller treats
        // empty output as "nothing to link yet" and retries on its next run.
        if (found) process.stdout.write(`${found}\n`);
        return;
    }
    setDefaultZoom(file);
}

const filename = fileURLToPath(import.meta.url);
if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        main(process.argv.slice(2));
    } catch (error) {
        console.error(`ERR ${error.message}`);
        process.exitCode = 1;
    }
}
