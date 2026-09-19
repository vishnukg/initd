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
    // Act
    const reading = status();

    // Assert: schema version is not consumed by the menu; compatible additions
    // must not fail the contract just because the producer bumps a number.
    assert.equal(typeof reading.daemon?.running, 'boolean', 'the daemon pill reads daemon.running');
    assert.ok(Array.isArray(reading.profiles), 'the Profiles section iterates status.profiles');
    assert.ok(Array.isArray(reading.monitors), 'the Displays section iterates status.monitors');
});

test('every field the Displays and Profiles sections read is present on this host', { skip: noHyprmoncfg }, t => {
    // Arrange
    const reading = status();

    // Act
    const monitors = reading.monitors;
    const profiles = reading.profiles;

    // Assert
    assert.ok(Array.isArray(monitors));
    assert.ok(Array.isArray(profiles));
    if (!monitors.length && !profiles.length) {
        t.skip('no monitors or saved profiles to check field contracts');
        return;
    }
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

    // An empty profile list is supported: the menu displays its setup hint.
    if (!profiles.length) t.diagnostic('no saved profiles; profile fields were not exercised');
    for (const profile of profiles) {
        // activeProfile and the recommendation marker key off exactly these.
        assert.equal(typeof profile.name, 'string');
        assert.equal(typeof profile.active, 'boolean');
        assert.equal(typeof profile.recommended, 'boolean');
        assert.equal(typeof profile.output_count, 'number', 'profileTag displays the output count');
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
