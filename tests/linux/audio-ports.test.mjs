import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parsePorts, readPorts } from '../../linux/scripts/audio-ports.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));

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
    const withoutPactlInstalled = run().status;

    // Assert
    assert.equal(withoutPactlInstalled, 1);
});

// pactl is a declared dependency of the Linux session, but a host without it
// skips rather than failing - the same guard the Fish and tmux checks use.
const locatedPactl = spawnSync('which', ['pactl'], { encoding: 'utf8' });
const noPactl = locatedPactl.status !== 0 && 'pactl is not installed';

test('cards whose ports arrive in an unrecognized shape are reported, not silently dropped', () => {
    // Arrange
    // Every other test feeds parsePorts a shape it understands. This is the
    // drift case: pactl changes `ports` to an array, every lookup fails open,
    // and without this warning the bar just shows every endpoint forever.
    const cards = [{ ports: [{ name: '[Out] HDMI1' }] }, { ports: 'unexpected' }];
    const warnings = [];

    // Act
    const ports = parsePorts(cards, message => warnings.push(message));

    // Assert
    assert.deepEqual(Object.keys(ports), []);
    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /2 card\(s\) carry ports in an unrecognized shape/);
});

test('a recognized card silences the drift warning even when another card is unreadable', () => {
    // Arrange
    const cards = [{ ports: ['unexpected'] }, { ports: { '[Out] Speaker': { availability: 'availability unknown' } } }];
    const warnings = [];

    // Act
    const ports = parsePorts(cards, message => warnings.push(message));

    // Assert
    assert.deepEqual(Object.keys(ports), ['Speaker']);
    assert.deepEqual(warnings, []);
});

test('the installed pactl still emits the card JSON parsePorts is written against', { skip: noPactl }, () => {
    // Arrange
    // The unit tests above prove the parser is self-consistent against fixtures
    // this repo wrote. Only this one notices when a pactl update invalidates the
    // assumptions those fixtures encode.
    const output = spawnSync('pactl', ['--format=json', 'list', 'cards'], {
        encoding: 'utf8', timeout: 10000, env: { ...process.env, LC_ALL: 'C' },
    });

    // Assert
    assert.equal(output.status, 0, output.stderr);

    // Act
    const cards = JSON.parse(output.stdout);
    const carded = cards.filter(card => card?.ports && Object.keys(card.ports).length > 0);

    // Assert
    assert.ok(Array.isArray(cards), 'the top level is still an array of cards');
    assert.ok(carded.length > 0, 'this host exposes at least one card with ports');
    for (const card of carded) {
        assert.ok(!Array.isArray(card.ports), 'ports is an object keyed by port name, not an array');
        for (const [key, port] of Object.entries(card.ports)) {
            assert.match(key, /^\[(?:Out|In)\] /, 'port keys still carry the direction prefix parsePorts strips');
            assert.equal(typeof port.availability, 'string', 'availability is the string "not available" is compared against');
        }
    }

    // Act
    const warnings = [];
    const ports = parsePorts(cards, message => warnings.push(message));

    // Assert
    assert.deepEqual(warnings, [], 'every card on this host parses');
    assert.ok(Object.keys(ports).length > 0, 'real output yields at least one port token');
    for (const [token, port] of Object.entries(ports)) {
        assert.doesNotMatch(token, /^\[/, 'the direction prefix is stripped from the joined token');
        assert.equal(typeof port.attached, 'boolean');
        assert.equal(typeof port.name, 'string');
    }
});
