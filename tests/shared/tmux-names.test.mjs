// names.sh: window emojis and space-themed session names, run from tmux hooks.
// Each test drives its own tmux server on a private socket. The script runs
// under /bin/bash where it exists, because macOS hooks get bash 3.2.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));
const tmuxDir = path.join(root, 'shared/configs/tmux/.config/tmux');
const script = path.join(tmuxDir, 'names.sh');
const bash = fs.existsSync('/bin/bash') ? '/bin/bash' : 'bash';
const noTmux = spawnSync('tmux', ['-V']).status !== 0 && 'tmux is not installed';
const options = { skip: noTmux || (process.env.INITD_TEST_TMUX !== '1' && 'set INITD_TEST_TMUX=1'), timeout: 20000 };
const pool = ['🧬', '🧪', '⚗️', '🔬', '🔭', '🧮', '📐', '🧩', '♾️', '🎲',
    '🚀', '🛸', '🛰️', '🪐', '☄️', '🦕', '🎮', '👾', '🤖', '💎', '🧲'];
const spaceNames = ['nova', 'vega', 'io', 'sol', 'luna', 'mars', 'lyra', 'titan', 'pluto', 'orion'];

function server(t, config = '/dev/null') {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-names-'));
    fs.mkdirSync(path.join(dir, '.config'));
    fs.symlinkSync(tmuxDir, path.join(dir, '.config/tmux'));
    const socket = path.join(dir, 's');
    const env = { ...process.env, HOME: dir };
    delete env.TMUX;
    delete env.TMUX_PANE;
    t.after(() => {
        spawnSync('tmux', ['-S', socket, 'kill-server'], { stdio: 'ignore' });
        // kill-server returns before the server has unlinked its socket here,
        // so the delete can race it: retry rather than fail on ENOTEMPTY.
        fs.rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 50 });
    });
    let started = false;
    const tmux = (...args) => {
        const first = started ? [] : ['-f', config];
        started = true;
        return execFileSync('tmux', ['-S', socket, ...first, ...args], { encoding: 'utf8', env }).trimEnd();
    };
    return {
        tmux,
        names: () => {
            const result = spawnSync(bash, [script], {
                encoding: 'utf8', env: { ...env, TMUX: `${socket},${tmux('display-message', '-p', '#{pid}')},0` },
            });
            assert.equal(result.status, 0, result.stderr);
            assert.equal(result.stdout + result.stderr, '');
        },
        sessions: () => tmux('list-sessions', '-F', '#{session_name}').split('\n').sort(),
        emojis: () => tmux('list-windows', '-a', '-F', '#{session_name}:#{window_index}\t#{@emoji}')
            .split('\n').map(line => line.split('\t')),
    };
}

test('numbered sessions get distinct free names; chosen names are kept whole', options, t => {
    // Arrange: "nova work" and "123 x" must neither be renamed nor count as
    // taking "nova".
    const { tmux, names, sessions } = server(t);
    for (const name of ['vega', null, null, 'notes', 'nova work', '123 x']) {
        tmux('new-session', '-d', ...(name ? ['-s', name] : []));
    }

    // Act
    names();

    // Assert
    assert.deepEqual(sessions(), ['123 x', 'io', 'nova', 'nova work', 'notes', 'vega'].sort());
});

test('session renaming stops when every name is taken rather than reusing one', options, t => {
    // Arrange
    const { tmux, names, sessions } = server(t);
    for (const name of spaceNames) tmux('new-session', '-d', '-s', name);
    tmux('new-session', '-d');
    const before = sessions();

    // Act
    names();

    // Assert: tmux would refuse a duplicate anyway.
    assert.deepEqual(sessions(), before);
});

test('every window gets a pool emoji, unused while any remain, kept once set', options, t => {
    // Arrange: one window already holds a pool emoji, one a retired icon.
    const { tmux, names, emojis } = server(t);
    tmux('new-session', '-d', '-s', 'a');
    for (let i = 0; i < 4; i++) tmux('new-window', '-t', 'a');
    tmux('set-option', '-w', '-t', 'a:0', '@emoji', '🧬');
    tmux('set-option', '-w', '-t', 'a:1', '@emoji', '🦄');

    // Act
    names();
    const first = emojis();
    names();

    // Assert
    assert.ok(first.every(([, emoji]) => pool.includes(emoji)), JSON.stringify(first));
    assert.equal(new Set(first.map(([, emoji]) => emoji)).size, first.length, 'no repeats while the pool lasts');
    assert.equal(first.find(([id]) => id === 'a:0')[1], '🧬');
    assert.deepEqual(emojis(), first, 'a second run changes nothing');
});

test('repeats are allowed once the pool is exhausted', options, t => {
    // Arrange
    const { tmux, names, emojis } = server(t);
    tmux('new-session', '-d', '-s', 'a');
    for (let i = 1; i < pool.length + 3; i++) tmux('new-window', '-t', 'a');

    // Act
    names();

    // Assert
    const all = emojis().map(([, emoji]) => emoji);
    assert.equal(all.length, pool.length + 3);
    assert.ok(all.every(emoji => pool.includes(emoji)));
    assert.equal(new Set(all).size, pool.length);
});

test('tmux.conf hooks name new sessions and decorate new windows', options, async t => {
    // Arrange
    const { tmux, sessions, emojis } = server(t, path.join(tmuxDir, 'tmux.conf'));
    tmux('new-session', '-d', '-s', 'work');

    // Act: tmux allocates a number; the hooks run in the background.
    tmux('new-session', '-d');
    tmux('new-window', '-t', 'work');
    const end = Date.now() + 5000;
    while ((sessions().some(name => /^\d+$/.test(name)) || emojis().some(([, e]) => !e)) && Date.now() < end) {
        await new Promise(resolve => setTimeout(resolve, 50));
    }

    // Assert
    assert.deepEqual(sessions(), ['nova', 'work']);
    assert.ok(emojis().every(([, emoji]) => pool.includes(emoji)), JSON.stringify(emojis()));
});
