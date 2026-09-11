import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parsePorts, readPorts } from '../linux/scripts/audio-ports.mjs';
import { main, parseArgs } from '../macos/brewinstall.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
function fixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-conversion-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'Brewfile');
    fs.writeFileSync(file, '# curated', { mode: 0o640 });
    const calls = [];
    return { dir, file, calls, log() {}, run(command, args) {
        assert.equal(command, 'brew');
        calls.push(args);
        return { status: args.includes('--cask') ? 1 : 0 };
    } };
}

test('audio card JSON preserves display names and only explicit unavailable ports are hidden', () => {
    const cards = [{ ports: {
        '[Out] HDMI1': { availability: 'available', properties: { 'device.product.name': 'Display | "wide"\nline' } },
        '[Out] HDMI2': { availability: 'not available' },
        '[In] Mic': { availability: 'availability unknown' },
        Speaker: {},
    } }];
    const ports = JSON.parse(JSON.stringify(parsePorts(cards)));
    assert.deepEqual(ports, {
        HDMI1: { attached: true, name: 'Display | "wide"\nline' },
        HDMI2: { attached: false, name: '' },
        Mic: { attached: true, name: '' },
        Speaker: { attached: true, name: '' },
    });
});

test('audio collisions across cards remain unmapped and malformed input is rejected', () => {
    const cards = [null, {}, ...[1, 2, 3].map(() => ({ ports: { '[Out] HDMI1': { availability: 'not available' } } }))];
    assert.deepEqual(Object.keys(parsePorts(cards)), []);
    for (const input of [null, {}, 'bad']) assert.throws(() => parsePorts(input), /card array/);
    assert.throws(() => readPorts(() => '{'), SyntaxError);
    assert.throws(() => readPorts(() => { throw new Error('daemon unavailable'); }), /daemon unavailable/);
});

test('audio CLI uses JSON pactl output and clears stale state on subprocess failure', t => {
    const { dir } = fixture(t);
    const pactl = path.join(dir, 'pactl');
    fs.writeFileSync(pactl, '#!/bin/sh\n[ "$1" = --format=json ] && [ "$2" = list ] && [ "$3" = cards ] || exit 9\nprintf \'[{"ports":{"[Out] HDMI1":{"availability":"available"}}}]\'\n', { mode: 0o755 });
    const run = () => spawnSync(process.execPath, [path.join(root, 'linux/scripts/audio-ports.mjs')], {
        env: { ...process.env, PATH: dir }, encoding: 'utf8', timeout: 10000,
    });
    const success = run();
    assert.equal(success.status, 0, success.stderr);
    assert.equal(JSON.parse(success.stdout).HDMI1.attached, true);
    fs.writeFileSync(pactl, '#!/bin/sh\nexit 3\n');
    const failed = run();
    assert.equal(failed.status, 1);
    assert.deepEqual(JSON.parse(failed.stdout), {});
    fs.unlinkSync(pactl);
    assert.equal(run().status, 1);
});

test('brewinstall validates arguments before running commands or editing files', t => {
    const f = fixture(t);
    for (const args of [[], ['--cask', '--formula', 'x'], ['a', 'b'], ['--bad'], ['x"'], ['#{system("bad")}'], ['x\ny'], ['-x']]) {
        assert.throws(() => main(args, f));
    }
    assert.deepEqual(f.calls, []);
    assert.equal(fs.readFileSync(f.file, 'utf8'), '# curated');
    assert.deepEqual(parseArgs(['--brew', 'user/tap/tool@2']), { kind: 'brew', name: 'user/tap/tool@2' });
});

test('brewinstall detects kind, preserves contents and mode, and retries without duplicating', t => {
    const f = fixture(t);
    main(['tool'], f);
    assert.equal(fs.readFileSync(f.file, 'utf8'), '# curated\nbrew "tool"\n');
    assert.equal(fs.statSync(f.file).mode & 0o777, 0o640);
    assert.deepEqual(f.calls.at(-1), ['bundle', '--file', f.file]);
    main(['--formula', 'tool'], f);
    assert.equal(fs.readFileSync(f.file, 'utf8'), '# curated\nbrew "tool"\n');
    assert.deepEqual(fs.readdirSync(f.dir), ['Brewfile']);
    fs.writeFileSync(f.file, '  brew "tool" # existing\ncask \'app\', greedy: true\n');
    main(['tool'], f);
    main(['--cask', 'app'], { ...f, run: () => ({ status: 0 }) });
    assert.equal(fs.readFileSync(f.file, 'utf8'), '  brew "tool" # existing\ncask \'app\', greedy: true\n');
});

test('brewinstall leaves the file untouched on ambiguous, missing or failed lookups', t => {
    const f = fixture(t);
    assert.throws(() => main(['tool'], { ...f, run: () => ({ status: 0 }) }), /both/);
    assert.throws(() => main(['tool'], { ...f, run: () => ({ status: 1 }) }), /Cannot resolve/);
    assert.throws(() => main(['--cask', 'tool'], f), /Cannot resolve/);
    assert.throws(() => main(['tool'], { ...f, run: () => ({ error: new Error('ENOENT') }) }), /ENOENT/);
    assert.throws(() => main(['tool'], { ...f, run: () => ({ signal: 'SIGTERM' }) }), /SIGTERM/);
    assert.equal(fs.readFileSync(f.file, 'utf8'), '# curated');
});

test('brewinstall reports bundle failure and retains the entry for a retry', t => {
    const f = fixture(t);
    assert.throws(() => main(['--formula', 'tool'], { ...f, run: (_command, args) => ({ status: args[0] === 'bundle' ? 1 : 0 }) }), /retained for retry/);
    assert.equal(fs.readFileSync(f.file, 'utf8'), '# curated\nbrew "tool"\n');
});

test('existing brewinstall command supports help and rejects invalid input without Homebrew', () => {
    const command = path.join(root, 'macos/brewinstall');
    const result = spawnSync(process.execPath, [command, '--help'], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Usage: brewinstall/);
    const bad = spawnSync(process.execPath, [command, 'bad"name'], { encoding: 'utf8' });
    assert.equal(bad.status, 1);
    assert.match(bad.stderr, /valid Homebrew package/);
});
