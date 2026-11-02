// The lock screen config must parse cleanly: a broken one could leave the
// session without a working lock. hyprlock parses its config before it
// connects to Wayland, so pointing it at a display that does not exist checks
// the config and exits without locking anything.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DEFAULT_THEME, renderHyprlock, themeFromScheme } from '../../linux/scripts/theme.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const config = path.join(root, 'linux/configs/hypr/hyprlock.conf');
const hasHyprlock = spawnSync('hyprlock', ['--version'], { encoding: 'utf8' }).status === 0;

function parse(file, home) {
    const result = spawnSync('hyprlock', ['--config', file, '--display', 'wayland-initd-test-none'], {
        encoding: 'utf8', timeout: 10000, env: { ...process.env, HOME: home, WAYLAND_DISPLAY: 'wayland-initd-test-none' },
    });
    return `${result.stdout}\n${result.stderr}`;
}

test('hyprlock.conf parses with no config errors, theme file present', { skip: !hasHyprlock && 'hyprlock not installed' }, () => {
    // Arrange: a home with a generated theme file, as after any wallpaper change.
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-lock-'));
    const state = path.join(home, '.local/state/initd');
    fs.mkdirSync(state, { recursive: true });
    fs.writeFileSync(path.join(state, 'hyprlock.conf'), renderHyprlock(themeFromScheme({ primary: '#ffb4a8', surface: '#1a1110' })));
    // Act
    const output = parse(config, home);
    // Assert
    assert.doesNotMatch(output, /Config error/, output);
});

test('hyprlock.conf still parses when the theme file is missing', { skip: !hasHyprlock && 'hyprlock not installed' }, () => {
    // A fresh machine before the first theme run: only the missing source is
    // reported, and hyprlock carries on with the defaults.
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-lock-'));
    const output = parse(config, home);
    const errors = output.split('\n').filter((line) => /Config error/.test(line));
    assert.ok(errors.every((line) => /source=/.test(line)), errors.join('\n'));
    assert.match(output, /Proceeding ignoring faulty entries|^\s*$/m);
});

test('the default hyprlock palette matches the theme defaults', () => {
    const lock = fs.readFileSync(config, 'utf8');
    for (const line of renderHyprlock(DEFAULT_THEME).split('\n').filter((l) => l.startsWith('$')))
        assert.ok(lock.includes(line), `hyprlock.conf default missing: ${line}`);
});
