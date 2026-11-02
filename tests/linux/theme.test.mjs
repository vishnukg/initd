// linux/scripts/theme.mjs: wallpaper -> palette -> every themed surface.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
    DEFAULT_THEME, applyTheme, ensureTheme, nearestAccent, outputs, parseMatugen,
    renderHyprlock, renderRofi, renderThemeJson, themeFromScheme, writeTheme,
} from '../../linux/scripts/theme.mjs';
import { THEME_DEFAULTS, themeColors } from '../../linux/configs/quickshell/bar-logic.mjs';

const tempHome = () => fs.mkdtempSync(path.join(os.tmpdir(), 'initd-theme-'));
const scheme = {
    primary: '#ffb4a8', on_primary: '#561e16', on_surface: '#f1dfdc', on_surface_variant: '#d8c2be',
    outline: '#a08c89', outline_variant: '#534341', surface: '#1a1110',
    surface_container_low: '#231918', surface_container_lowest: '#140c0b',
};

test('the bar and the theme script agree on the default palette', () => {
    for (const role of Object.keys(THEME_DEFAULTS))
        assert.equal(DEFAULT_THEME[role], THEME_DEFAULTS[role], role);
});

test('parseMatugen reads each JSON shape matugen has used', () => {
    for (const json of [
        { colors: { primary: { dark: '#FFB4A8' }, surface: { dark: '#1a1110' } } },
        { colors: { primary: { dark: { color: '#ffb4a8' } }, surface: { dark: { color: '#1a1110' } } } },
        { colors: { dark: { primary: '#ffb4a8', surface: '#1a1110' } } },
        { colors: { primary: '#ffb4a8', surface: '#1a1110' } },
    ]) {
        const parsed = parseMatugen(JSON.stringify(json));
        assert.equal(parsed.primary, '#ffb4a8', JSON.stringify(json));
        assert.equal(parsed.surface, '#1a1110');
    }
});

test('parseMatugen refuses output without the roles the theme needs', () => {
    assert.throws(() => parseMatugen('{}'));
    assert.throws(() => parseMatugen('{"colors": {"primary": {"dark": "#ffffff"}}}'));
    assert.throws(() => parseMatugen('not json'));
});

test('themeFromScheme maps Material roles and keeps status colours fixed', () => {
    // Act
    const theme = themeFromScheme(scheme);
    // Assert
    assert.equal(theme.accent, '#ffb4a8');
    assert.equal(theme.onAccent, '#561e16');
    assert.equal(theme.text, '#f1dfdc');
    assert.equal(theme.surface, '#231918');
    assert.equal(theme.bar, '#b3140c0b');
    assert.equal(theme.menu, '#f2231918');
    assert.equal(theme.bad, DEFAULT_THEME.bad);
    assert.equal(theme.good, DEFAULT_THEME.good);
});

test('the generated theme.json is accepted role for role by the bar', () => {
    const theme = themeFromScheme(scheme);
    const colors = themeColors(renderThemeJson(theme, '/w.jpg'));
    for (const role of Object.keys(THEME_DEFAULTS)) assert.equal(colors[role], theme[role], role);
});

test('nearestAccent picks GNOME\'s named accent by hue, slate when grey', () => {
    assert.equal(nearestAccent('#8fb7e8'), 'blue');
    assert.equal(nearestAccent('#ff6f61'), 'red');
    assert.equal(nearestAccent('#ffa060'), 'orange');
    assert.equal(nearestAccent('#a6d396'), 'green');
    assert.equal(nearestAccent('#d0bcff'), 'purple');
    assert.equal(nearestAccent('#f5c56d'), 'yellow');
    assert.equal(nearestAccent('#82d3e0'), 'teal');
    assert.equal(nearestAccent('#9a9a9e'), 'slate');
});

test('renderers emit the syntax each consumer parses', () => {
    const theme = themeFromScheme(scheme);
    assert.match(renderRofi(theme), /accent:\s+#ffb4a8;/);
    assert.match(renderRofi(theme), /surface:\s+#231918e0;/);
    assert.match(renderHyprlock(theme), /^\$accent = rgba\(ffb4a8ff\)$/m);
    assert.match(renderHyprlock(theme), /^\$surface = rgba\(231918cc\)$/m);
});

test('ensureTheme writes defaults only for missing files', () => {
    // Arrange
    const home = tempHome();
    const files = outputs(home);
    fs.mkdirSync(path.dirname(files.rofi), { recursive: true });
    fs.writeFileSync(files.rofi, 'kept');
    // Act
    const written = ensureTheme({ home });
    // Assert
    assert.equal(fs.readFileSync(files.rofi, 'utf8'), 'kept');
    assert.equal(written.length, 3);
    assert.deepEqual(themeColors(fs.readFileSync(files.json, 'utf8')), THEME_DEFAULTS);
    assert.deepEqual(ensureTheme({ home }), []);
});

test('applyTheme writes every output from the image\'s scheme', () => {
    // Arrange
    const home = tempHome();
    const image = path.join(home, 'w.jpg');
    fs.writeFileSync(image, 'x');
    const calls = [];
    const run = (command, args) => {
        calls.push([command, ...args]);
        if (command === 'matugen') return 'log line\n' + JSON.stringify({ colors: Object.fromEntries(
            Object.entries(scheme).map(([k, v]) => [k, { dark: v }])) });
        return '';
    };
    // Act
    applyTheme(image, { home, run });
    // Assert
    const json = JSON.parse(fs.readFileSync(outputs(home).json, 'utf8'));
    assert.equal(json.wallpaper, image);
    assert.equal(json.colors.accent, '#ffb4a8');
    assert.ok(calls.some((c) => c[0] === 'gsettings' && c.includes(nearestAccent('#ffb4a8'))));
    assert.match(fs.readFileSync(outputs(home).gtk3, 'utf8'), /accent_bg_color #ffb4a8/);
});

test('applyTheme leaves the current theme alone when matugen fails', () => {
    // Arrange
    const home = tempHome();
    const image = path.join(home, 'w.jpg');
    fs.writeFileSync(image, 'x');
    writeTheme(DEFAULT_THEME, { home });
    const before = fs.readFileSync(outputs(home).json, 'utf8');
    const run = () => { throw new Error('matugen: command not found'); };
    // Act / Assert
    assert.throws(() => applyTheme(image, { home, run }), /command not found/);
    assert.equal(fs.readFileSync(outputs(home).json, 'utf8'), before);
    assert.throws(() => applyTheme(path.join(home, 'missing.jpg'), { home, run }), /no such image/);
});
