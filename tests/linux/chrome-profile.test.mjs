import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { configureChrome, setDefaultBrowser, BROWSER } from '../../linux/scripts/chrome-profile.mjs';

function fixture(t, status = 1) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-chrome-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    const configHome = path.join(home, '.config');
    const dataHome = path.join(home, '.local/share');
    const root = path.join(configHome, 'google-chrome');
    const profile = path.join(root, 'Profile 2');
    fs.mkdirSync(profile, { recursive: true });
    fs.writeFileSync(path.join(root, 'Local State'), JSON.stringify({ profile: { last_used: 'Profile 2' } }));
    const preferences = path.join(profile, 'Preferences');
    const current = { partition: { per_host_zoom_levels: { x: { 'example.org': { zoom_level: 2 } } } }, webkit: { webprefs: { fonts: { standard: { Zyyy: 'My Font' } } } }, browser: { theme: { color_scheme2: 2 } } };
    fs.writeFileSync(preferences, JSON.stringify(current));
    const desktop = path.join(home, 'system.desktop');
    fs.writeFileSync(desktop, '[Desktop Entry]\nExec=/usr/bin/google-chrome-stable %U\n[Desktop Action new-window]\nExec=/usr/bin/google-chrome-stable\n[Desktop Action new-private-window]\nExec=/usr/bin/google-chrome-stable --incognito\n');
    return { preferences, profile, current, options: { home, configHome, dataHome, desktop, run: () => ({ status }), log() {}, warn() {} } };
}

test('Chrome setup preserves user choices and site zoom, backs up once and scales every launcher action', t => {
    // Arrange
    const f = fixture(t);
    const before = fs.readFileSync(f.preferences, 'utf8');

    // Act
    configureChrome(f.options);
    configureChrome(f.options);
    const actual = JSON.parse(fs.readFileSync(f.preferences, 'utf8'));
    const launcher = fs.readFileSync(path.join(f.options.dataHome, 'applications/google-chrome.desktop'), 'utf8');
    const backups = fs.readdirSync(f.profile).filter(name => name.includes('.initd-backup-'));

    // Assert
    assert.equal(backups.length, 1);
    assert.equal(fs.readFileSync(path.join(f.profile, backups[0]), 'utf8'), before);
    assert.ok(Math.abs(1.2 ** actual.partition.default_zoom_level.x - 1.15) < 1e-12);
    assert.equal(actual.webkit.webprefs.default_font_size, 17);
    assert.equal(actual.webkit.webprefs.default_fixed_font_size, 14);
    assert.deepEqual(actual.partition.per_host_zoom_levels, f.current.partition.per_host_zoom_levels);
    assert.deepEqual(actual.webkit.webprefs.fonts, f.current.webkit.webprefs.fonts);
    assert.deepEqual(actual.browser, f.current.browser);
    assert.equal(launcher.match(/--force-device-scale-factor=1\.2/g).length, 3);
    assert.match(launcher, /--force-device-scale-factor=1\.2 %U/);
    assert.match(launcher, /--force-device-scale-factor=1\.2 --incognito/);
});

for (const status of [0, 2, null]) {
    test(`Chrome profile remains untouched when process check returns ${status}`, t => {
        // Arrange
        const f = fixture(t, status);
        const before = fs.readFileSync(f.preferences, 'utf8');

        // Act
        configureChrome(f.options);

        // Assert
        assert.equal(fs.readFileSync(f.preferences, 'utf8'), before);
        assert.deepEqual(fs.readdirSync(f.profile), ['Preferences']);
    });
}

// Records every command and answers xdg-settings from `answers`, pgrep with 1
// (Chrome not running).
function recorder(answers) {
    const calls = [];
    const run = (command, args) => {
        calls.push([command, ...args]);
        if (command === 'xdg-settings') return answers[args[0]];
        return { status: 1 };
    };
    return { calls, run };
}

test('Chrome becomes the default browser when something else is', () => {
    // Arrange
    const { calls, run } = recorder({ get: { status: 0, stdout: 'org.mozilla.firefox.desktop\n' }, set: { status: 0 } });
    const warnings = [];

    // Act
    setDefaultBrowser({ run, log() {}, warn: message => warnings.push(message) });

    // Assert
    assert.deepEqual(calls.at(-1), ['xdg-settings', 'set', 'default-web-browser', BROWSER]);
    assert.deepEqual(warnings, []);
});

test('Default browser is left alone when Chrome already holds it', () => {
    // Arrange
    const { calls, run } = recorder({ get: { status: 0, stdout: `${BROWSER}\n` } });

    // Act
    setDefaultBrowser({ run, log() {}, warn() {} });

    // Assert
    assert.deepEqual(calls, [['xdg-settings', 'get', 'default-web-browser']]);
});

test('A failed default-browser change warns and the profile is still configured', t => {
    // Arrange
    const f = fixture(t);
    const { calls, run } = recorder({ get: { status: 1 }, set: { status: 3, stderr: 'xdg-settings: boom\n' } });
    const warnings = [];

    // Act
    configureChrome({ ...f.options, run, warn: message => warnings.push(message) });
    const actual = JSON.parse(fs.readFileSync(f.preferences, 'utf8'));

    // Assert
    assert.ok(calls.some(call => call.join(' ') === `xdg-settings set default-web-browser ${BROWSER}`));
    assert.deepEqual(warnings, ['Could not make Chrome the default browser: xdg-settings: boom']);
    assert.equal(actual.webkit.webprefs.default_font_size, 17);
});
