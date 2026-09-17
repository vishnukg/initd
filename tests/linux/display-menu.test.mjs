// DisplayMenu.qml parses `hyprmoncfg status --json` inline - there is no
// JavaScript module between the tool and the bar, so nothing else in this suite
// would notice the day hyprmoncfg renames a field. These checks assert only the
// keys that popup actually reads.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));
const located = spawnSync('which', ['hyprmoncfg'], { encoding: 'utf8' });
const noHyprmoncfg = located.status !== 0 && 'hyprmoncfg is not installed';

function status() {
    const result = spawnSync('hyprmoncfg', ['status', '--json'], { encoding: 'utf8', timeout: 10000 });
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
}

test('hyprmoncfg still speaks the status schema DisplayMenu is written against', { skip: noHyprmoncfg }, () => {
    // Arrange
    // hyprmoncfg versions its own output, so the cheapest possible drift alarm
    // is to pin the number and let a bump fail here rather than in the bar.
    const expectedSchema = 1;

    // Act
    const reading = status();

    // Assert
    assert.equal(reading.schema_version, expectedSchema,
        `hyprmoncfg ${reading.version} changed its status schema; re-read DisplayMenu.qml's parse block`);
    assert.equal(typeof reading.daemon?.running, 'boolean', 'the daemon pill reads daemon.running');
    assert.ok(Array.isArray(reading.profiles), 'the Profiles section iterates status.profiles');
    assert.ok(Array.isArray(reading.monitors), 'the Displays section iterates status.monitors');
});

test('every field the Displays and Profiles sections read is present on this host', { skip: noHyprmoncfg }, () => {
    // Arrange
    const reading = status();

    // Act
    const monitors = reading.monitors;
    const profiles = reading.profiles;

    // Assert
    assert.ok(monitors.length > 0, 'a running session has at least one monitor');
    for (const monitor of monitors) {
        // monitorLabel() falls back make -> model -> name, and the mode tag is
        // built from width/height/refresh_rate/scale.
        assert.equal(typeof monitor.name, 'string');
        assert.equal(typeof monitor.enabled, 'boolean');
        assert.equal(typeof monitor.internal, 'boolean');
        assert.equal(typeof monitor.width, 'number');
        assert.equal(typeof monitor.height, 'number');
        assert.equal(typeof monitor.refresh_rate, 'number');
        assert.equal(typeof monitor.scale, 'number');
        for (const key of ['make', 'model']) {
            assert.ok(monitor[key] === undefined || typeof monitor[key] === 'string', `${key} is a string when present`);
        }
    }

    assert.ok(profiles.length > 0, 'at least one saved profile to switch between');
    for (const profile of profiles) {
        // activeProfile and the recommendation marker key off exactly these.
        assert.equal(typeof profile.name, 'string');
        assert.equal(typeof profile.active, 'boolean');
        assert.equal(typeof profile.recommended, 'boolean');
    }
    assert.ok(profiles.filter(profile => profile.active).length <= 1, 'at most one profile is active');
});

test('apply is still invoked with the confirmation prompt disabled', () => {
    // Arrange
    // Without --confirm-timeout 0, apply prompts, reads EOF from a popup that
    // has no tty, reverts the profile and exits 1. This is a source assertion
    // rather than a live one: running apply would relayout the real session.
    const menu = fs.readFileSync(path.join(root, 'linux/configs/quickshell/DisplayMenu.qml'), 'utf8');

    // Act
    const applyCommand = menu.match(/"hyprmoncfg",\s*"apply"[^\]]*/);

    // Assert
    assert.ok(applyCommand, 'DisplayMenu still shells out to hyprmoncfg apply');
    assert.match(applyCommand[0], /"--confirm-timeout",\s*"0"/);
});
