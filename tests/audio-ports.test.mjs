import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parsePorts, readPorts } from '../linux/scripts/audio-ports.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));

test('audio card JSON preserves display names and only explicit unavailable ports are hidden', () => {
    // Arrange
    const cards = [{ ports: {
        '[Out] HDMI1': { availability: 'available', properties: { 'device.product.name': 'Display | "wide"\nline' } },
        '[Out] HDMI2': { availability: 'not available' },
        '[In] Mic': { availability: 'availability unknown' },
        Speaker: {},
    } }];

    // Act
    const ports = JSON.parse(JSON.stringify(parsePorts(cards)));

    // Assert
    assert.deepEqual(ports, {
        HDMI1: { attached: true, name: 'Display | "wide"\nline' },
        HDMI2: { attached: false, name: '' },
        Mic: { attached: true, name: '' },
        Speaker: { attached: true, name: '' },
    });
});

test('audio collisions across cards remain unmapped', () => {
    // Arrange
    const cards = [null, {}, ...[1, 2, 3].map(() => ({ ports: { '[Out] HDMI1': { availability: 'not available' } } }))];

    // Act
    const ports = parsePorts(cards);

    // Assert
    assert.deepEqual(Object.keys(ports), []);
});

for (const input of [null, {}, 'bad']) {
    test(`parsePorts rejects malformed input ${JSON.stringify(input)}`, () => {
        // Arrange
        const cards = input;

        // Act: defer the call so assert.throws observes the error.
        const parse = () => parsePorts(cards);

        // Assert
        assert.throws(parse, /card array/);
    });
}

for (const { name, read, expectedError } of [
    { name: 'malformed JSON', read: () => '{', expectedError: SyntaxError },
    { name: 'daemon failure', read: () => { throw new Error('daemon unavailable'); }, expectedError: /daemon unavailable/ },
]) {
    test(`readPorts reports ${name}`, () => {
        // Arrange
        const readCards = read;

        // Act: defer the call so assert.throws observes the error.
        const readAudioPorts = () => readPorts(readCards);

        // Assert
        assert.throws(readAudioPorts, expectedError);
    });
}

test('audio CLI uses JSON pactl output and clears stale state on subprocess failure', t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-audio-ports-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const pactl = path.join(dir, 'pactl');
    fs.writeFileSync(pactl, '#!/bin/sh\n[ "$1" = --format=json ] && [ "$2" = list ] && [ "$3" = cards ] || exit 9\nprintf \'[{"ports":{"[Out] HDMI1":{"availability":"available"}}}]\'\n', { mode: 0o755 });
    const run = () => spawnSync(process.execPath, [path.join(root, 'linux/scripts/audio-ports.mjs')], {
        env: { ...process.env, PATH: dir }, encoding: 'utf8', timeout: 10000,
    });

    // Act
    const success = run();

    // Assert
    assert.equal(success.status, 0, success.stderr);
    assert.equal(JSON.parse(success.stdout).HDMI1.attached, true);

    // Arrange
    fs.writeFileSync(pactl, '#!/bin/sh\nexit 3\n');

    // Act
    const failed = run();

    // Assert
    assert.equal(failed.status, 1);
    assert.deepEqual(JSON.parse(failed.stdout), {});

    // Arrange
    fs.unlinkSync(pactl);

    // Act
    const runResult = run().status;

    // Assert
    assert.equal(runResult, 1);
});
