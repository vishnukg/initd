import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { configureBrave, setDefaultBrowser, withSettings, BROWSER, PREFERENCES, LOCAL_STATE } from '../../linux/scripts/brave-profile.mjs';

function fixture(t, status = 1) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-brave-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    const configHome = path.join(home, '.config');
    const dataHome = path.join(home, '.local/share');
    const root = path.join(configHome, 'BraveSoftware', 'Brave-Browser');
    const profile = path.join(root, 'Profile 2');
    fs.mkdirSync(profile, { recursive: true });
    fs.writeFileSync(path.join(root, 'Local State'), JSON.stringify({ profile: { last_used: 'Profile 2' }, brave: { p3a: { enabled: true, randomness_meta: { express: 4 } } } }));
    const preferences = path.join(profile, 'Preferences');
    const current = { partition: { per_host_zoom_levels: { x: { 'example.org': { zoom_level: 2 } } } }, webkit: { webprefs: { fonts: { standard: { Zyyy: 'My Font' } } } }, browser: { theme: { color_scheme2: 2 } } };
    fs.writeFileSync(preferences, JSON.stringify(current));
    const desktop = path.join(home, 'system.desktop');
    fs.writeFileSync(desktop, '[Desktop Entry]\nExec=/usr/bin/brave-browser-stable %U\n[Desktop Action new-window]\nExec=/usr/bin/brave-browser-stable\n[Desktop Action new-private-window]\nExec=/usr/bin/brave-browser-stable --incognito\n');
    return { preferences, profile, current, options: { home, configHome, dataHome, desktop, run: () => ({ status }), log() {}, warn() {} } };
}

test('Brave setup preserves user choices and site zoom, backs up once and scales every launcher action', t => {
    // Arrange
    const f = fixture(t);
    const before = fs.readFileSync(f.preferences, 'utf8');

    // Act
    configureBrave(f.options);
    configureBrave(f.options);
    const actual = JSON.parse(fs.readFileSync(f.preferences, 'utf8'));
    const launcher = fs.readFileSync(path.join(f.options.dataHome, 'applications/brave-browser.desktop'), 'utf8');
    const backups = fs.readdirSync(f.profile).filter(name => name.includes('.initd-backup-'));

    // Assert
    assert.equal(backups.length, 1);
    assert.equal(fs.readFileSync(path.join(f.profile, backups[0]), 'utf8'), before);
    assert.ok(Math.abs(1.2 ** actual.partition.default_zoom_level.x - 1.15) < 1e-12);
    assert.equal(actual.webkit.webprefs.default_font_size, 17);
    assert.equal(actual.webkit.webprefs.default_fixed_font_size, 14);
    assert.deepEqual(actual.partition.per_host_zoom_levels, f.current.partition.per_host_zoom_levels);
    assert.deepEqual(actual.webkit.webprefs.fonts, f.current.webkit.webprefs.fonts);
    assert.deepEqual(actual.browser.theme, f.current.browser.theme);
    assert.equal(launcher.match(/--force-device-scale-factor=1\.2/g).length, 3);
    assert.match(launcher, /--force-device-scale-factor=1\.2 %U/);
    assert.match(launcher, /--force-device-scale-factor=1\.2 --incognito/);
});

test('Brave setup applies the captured toggles, Google search and Local State, keeping what the browser wrote', t => {
    // Arrange
    const f = fixture(t);
    const stateFile = path.join(f.options.configHome, 'BraveSoftware/Brave-Browser/Local State');

    // Act
    configureBrave(f.options);
    const prefs = JSON.parse(fs.readFileSync(f.preferences, 'utf8'));
    const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));

    // Assert
    assert.equal(prefs.brave.ai_chat.show_toolbar_button, false);
    assert.equal(prefs.brave.rewards.show_brave_rewards_button_in_location_bar, false);
    assert.equal(prefs.brave.wallet.show_wallet_icon_on_toolbar, false);
    assert.equal(prefs.omnibox.prevent_url_elisions, true);
    assert.equal(prefs.browser.custom_chrome_frame, false);
    assert.equal(prefs.default_search_provider_data.template_url_data.short_name, 'Google');
    assert.equal(prefs.default_search_provider_data.template_url_data.prepopulate_id, 1);
    assert.equal(prefs.brave.default_private_search_provider_data.short_name, 'Google');
    assert.equal('synced_guid' in prefs.default_search_provider_data.template_url_data, false, 'no identity copied from the source profile');
    assert.equal(state.brave.p3a.enabled, false);
    assert.equal(state.user_experience_metrics.reporting_enabled, false);
    assert.deepEqual(state.brave.p3a.randomness_meta, { express: 4 }, 'sibling keys survive');
    assert.equal(state.profile.last_used, 'Profile 2');
});

test('withSettings sets dotted paths on a copy, merges objects and replaces arrays whole', () => {
    // Arrange: `engine` stands for a search dictionary the browser already wrote, ids included
    const current = { a: { keep: 1, list: [1, 2, 3] }, scalar: 'x', engine: { id: '4', short_name: 'Brave', urls: ['old'] } };

    // Act
    const next = withSettings(current, {
        'a.list': [9], 'a.b.c': true, 'scalar.now': 'object',
        engine: { short_name: 'Google', urls: ['new'] },
    });

    // Assert
    assert.deepEqual(next, {
        a: { keep: 1, list: [9], b: { c: true } }, scalar: { now: 'object' },
        engine: { id: '4', short_name: 'Google', urls: ['new'] },
    });
    assert.deepEqual(current.engine, { id: '4', short_name: 'Brave', urls: ['old'] }, 'the input is not mutated');
});

test('every captured preference and Local State key is a dotted path with a JSON value', () => {
    for (const [key, value] of [...Object.entries(PREFERENCES), ...Object.entries(LOCAL_STATE)]) {
        assert.match(key, /^[a-z0-9_-]+(\.[a-z0-9_-]+)+$/i, key);
        assert.notEqual(value, undefined, key);
    }
});

for (const status of [0, 2, null]) {
    test(`Brave profile remains untouched when process check returns ${status}`, t => {
        // Arrange
        const f = fixture(t, status);
        const before = fs.readFileSync(f.preferences, 'utf8');

        // Act
        configureBrave(f.options);

        // Assert
        assert.equal(fs.readFileSync(f.preferences, 'utf8'), before);
        assert.deepEqual(fs.readdirSync(f.profile), ['Preferences']);
    });
}

// Records every command and answers xdg-settings from `answers`, pgrep with 1
// (Brave not running).
function recorder(answers) {
    const calls = [];
    const run = (command, args) => {
        calls.push([command, ...args]);
        if (command === 'xdg-settings') return answers[args[0]];
        return { status: 1 };
    };
    return { calls, run };
}

test('Brave becomes the default browser when something else is', () => {
    // Arrange
    const { calls, run } = recorder({ get: { status: 0, stdout: 'org.mozilla.firefox.desktop\n' }, set: { status: 0 } });
    const warnings = [];

    // Act
    setDefaultBrowser({ run, log() {}, warn: message => warnings.push(message) });

    // Assert
    assert.deepEqual(calls.at(-1), ['xdg-settings', 'set', 'default-web-browser', BROWSER]);
    assert.deepEqual(warnings, []);
});

test('Default browser is left alone when Brave already holds it', () => {
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
    configureBrave({ ...f.options, run, warn: message => warnings.push(message) });
    const actual = JSON.parse(fs.readFileSync(f.preferences, 'utf8'));

    // Assert
    assert.ok(calls.some(call => call.join(' ') === `xdg-settings set default-web-browser ${BROWSER}`));
    assert.deepEqual(warnings, ['Could not make Brave the default browser: xdg-settings: boom']);
    assert.equal(actual.webkit.webprefs.default_font_size, 17);
});
