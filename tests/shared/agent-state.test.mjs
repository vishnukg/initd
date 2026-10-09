// agent-state.sh and the tmux.conf pieces that read it: hook transitions, tab
// icons, the cross-session status pill, "done" clearing once seen, C-a a and
// the C-a g picker. Every test runs its own tmux server on a private socket with
// a temporary HOME whose ~/.config/tmux links back to this repo, so the real
// bindings and hooks are what is exercised.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));
const tmuxDir = path.join(root, 'shared/configs/tmux/.config/tmux');
const script = path.join(tmuxDir, 'agent-state.sh');
const noTmux = spawnSync('tmux', ['-V']).status !== 0 && 'tmux is not installed';
const skip = noTmux || (process.env.INITD_TEST_TMUX !== '1' && 'set INITD_TEST_TMUX=1');
const noFzf = spawnSync('fzf', ['--version']).status !== 0 && 'fzf is not installed';
const options = { skip, timeout: 20000 };
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function waitUntil(predicate, description) {
    const end = Date.now() + 5000;
    while (!predicate()) {
        if (Date.now() >= end) throw new Error(`timed out waiting for ${description}`);
        await delay(50);
    }
}

// A tmux server loaded with the repo's tmux.conf. Agents are node hard-linked
// (or copied) as "claude", which is what #{pane_current_command} reports.
async function server(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-'));
    fs.mkdirSync(path.join(dir, '.config'));
    fs.mkdirSync(path.join(dir, 'bin'));
    fs.symlinkSync(tmuxDir, path.join(dir, '.config/tmux'));
    const claude = path.join(dir, 'bin/claude');
    try { fs.linkSync(process.execPath, claude); } catch { fs.copyFileSync(process.execPath, claude); }
    fs.chmodSync(claude, 0o755);
    const socket = path.join(dir, 's');
    const outer = path.join(dir, 'o');
    const env = { ...process.env, HOME: dir };
    delete env.TMUX;
    delete env.TMUX_PANE;
    t.after(() => {
        for (const s of [outer, socket]) spawnSync('tmux', ['-S', s, 'kill-server'], { stdio: 'ignore' });
        // kill-server returns before the server has unlinked its socket here,
        // so the delete can race it: retry rather than fail on ENOTEMPTY.
        fs.rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 50 });
    });

    const tmux = (...args) => execFileSync('tmux', ['-S', socket, ...args], { encoding: 'utf8', env }).trimEnd();
    const agent = `${claude} -e 'setInterval(Object, 1e9)'`;
    tmux('-f', path.join(tmuxDir, 'tmux.conf'), 'new-session', '-d', '-s', 'nova', '-x', '120', '-y', '30', agent);
    tmux('new-window', '-t', 'nova', agent);
    tmux('new-session', '-d', '-s', 'vega', '-x', '120', '-y', '30', agent);
    await waitUntil(() => tmux('list-panes', '-a', '-F', '#{pane_current_command}').split('\n')
        .every(command => command === 'claude'), 'every agent pane to report claude');
    const [nova0, nova1, vega0] = tmux('list-panes', '-a', '-F', '#{pane_id}').split('\n');
    const serverPid = tmux('display-message', '-p', '#{pid}');

    return {
        tmux, agent, panes: { nova0, nova1, vega0 },
        // What a Claude Code hook does: run the script with the agent's own
        // $TMUX/$TMUX_PANE inherited.
        hook(pane, state) {
            return spawnSync(script, [state], {
                encoding: 'utf8', env: { ...env, TMUX: `${socket},${serverPid},0`, TMUX_PANE: pane },
            });
        },
        state: pane => tmux('display-message', '-p', '-t', pane, '#{@agent-state}'),
        since: pane => tmux('display-message', '-p', '-t', pane, '#{@agent-since}'),
        // A real client, attached from inside a second server's pane so that it
        // has a terminal; keys typed there go through the C-a prefix like yours.
        async attach(pane) {
            execFileSync('tmux', ['-S', outer, '-f', '/dev/null', 'new-session', '-d', '-x', '120', '-y', '30',
                `tmux -S ${socket} attach -t ${pane}`], { env });
            await waitUntil(() => tmux('list-clients', '-F', '#{client_name}') !== '', 'the client to attach');
            tmux('switch-client', '-t', pane);
            return {
                type: async (...keys) => {
                    for (const key of keys) {
                        execFileSync('tmux', ['-S', outer, 'send-keys', key], { env });
                        await delay(150);
                    }
                },
                at: () => tmux('list-clients', '-F', '#{pane_id}'),
            };
        },
    };
}

test('hooks record transitions on the agent pane and stay silent', options, async t => {
    // Arrange
    const { hook, state, since, tmux, panes: { nova0 } } = await server(t);

    // Act
    const results = ['working', 'blocked', 'clear'].map(s => [s, hook(nova0, s)]);

    // Assert: hook stdout would become model context.
    for (const [s, result] of results) {
        assert.equal(result.status, 0, s);
        assert.equal(result.stdout + result.stderr, '', s);
    }
    assert.equal(state(nova0), '');
    assert.equal(since(nova0), '');

    // Arrange: a repeat event is not a transition.
    hook(nova0, 'blocked');
    tmux('set-option', '-p', '-t', nova0, '@agent-since', '1');

    // Act
    hook(nova0, 'blocked');

    // Assert: "blocked for 5m" must keep meaning five minutes.
    assert.equal(since(nova0), '1');

    // Act: idle_prompt must never hide a blocked agent.
    hook(nova0, 'settle');

    // Assert
    assert.equal(state(nova0), 'blocked');

    // Act: but it does settle an Esc-interrupted turn (no client: unseen).
    hook(nova0, 'working');
    hook(nova0, 'settle');

    // Assert
    assert.equal(state(nova0), 'done');
});

test('each tab shows its most urgent agent, and nothing for a dead one', options, async t => {
    // Arrange
    const { hook, tmux, panes: { nova0, nova1 } } = await server(t);
    const dot = pane => tmux('display-message', '-p', '-t', pane, '#{E:@agent-dot}');
    const split = tmux('split-window', '-P', '-F', '#{pane_id}', '-t', nova1, 'sh');

    // Act
    hook(nova0, 'working');
    hook(nova1, 'done');
    tmux('set-option', '-p', '-t', split, '@agent-state', 'blocked');

    // Assert: a blocked state on a pane that is not running claude is ignored.
    assert.match(dot(nova0), /fg=#e0af68\]#\[bold\]\u{F051F}/u);
    assert.match(dot(nova1), /\u{F012C}/u);

    // Act: blocked outranks done within one window.
    hook(nova1, 'blocked');

    // Assert
    assert.match(dot(nova1), /fg=#f7768e\]#\[bold\]\u{F0028}/u);

    // Act: the agent dies without SessionEnd, leaving its state behind.
    tmux('respawn-pane', '-k', '-t', nova0, 'sh');
    await waitUntil(() => tmux('display-message', '-p', '-t', nova0, '#{pane_current_command}') !== 'claude', 'the agent to be replaced');

    // Assert
    assert.equal(dot(nova0), '');
});

test('the status pill counts agents per state across every session', options, async t => {
    // Arrange
    const { hook, tmux, panes: { nova0, nova1, vega0 } } = await server(t);
    const pill = () => tmux('display-message', '-p', '-t', 'nova', '#{E:@agent-pill}')
        .replace(/#\[[^\]]*\]/g, '');

    // Act
    const none = pill();
    hook(nova0, 'blocked');
    hook(vega0, 'blocked');
    hook(nova1, 'working');
    const mixed = pill();

    // Assert: blocked in two sessions, one working, and no done segment at zero.
    assert.equal(none, '');
    assert.match(mixed, /\u{F0028} 2 \u{F051F} 1 /u);
    assert.doesNotMatch(mixed, /\u{F012C}/u);

    // Act
    hook(nova1, 'done');
    hook(nova0, 'clear');
    hook(vega0, 'clear');

    // Assert
    assert.match(pill(), /\u{F012C} 1 /u);
    assert.doesNotMatch(pill(), /\u{F0028}|\u{F051F}/u);
});

test('picker rows survive spaces in session and directory names', options, async t => {
    // Arrange
    const { hook, tmux, agent } = await server(t);
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd agent '));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    tmux('rename-session', '-t', 'nova', 'side quest');
    const pane = tmux('new-window', '-P', '-F', '#{pane_id}', '-c', dir, '-t', 'side quest', agent);
    await waitUntil(() => tmux('display-message', '-p', '-t', pane, '#{pane_current_command}') === 'claude', 'the agent');
    hook(pane, 'blocked');

    // Act
    const rows = tmux('run-shell', `${script} list`).replace(/\x1b\[[0-9;]*m/g, '').split('\n');
    const row = rows.find(line => line.startsWith(`${pane}\t`));

    // Assert: the state column is still the state, and both names are whole.
    assert.match(row, /\u{F0028} blocked +side quest:\d+ /u);
    assert.ok(row.endsWith(path.basename(dir)), row);
});

test('C-a a visits blocked agents oldest first and skips the one you are in', options, async t => {
    // Arrange
    const { hook, tmux, attach, panes: { nova0, nova1, vega0 } } = await server(t);
    hook(nova1, 'blocked');
    hook(vega0, 'blocked');
    tmux('set-option', '-p', '-t', nova1, '@agent-since', '200');
    tmux('set-option', '-p', '-t', vega0, '@agent-since', '100');
    const client = await attach(nova0);

    // Act
    await client.type('C-a', 'a');
    const first = client.at();
    await client.type('C-a', 'a');
    const second = client.at();
    hook(nova1, 'working');
    hook(vega0, 'working');
    await client.type('C-a', 'a');
    const none = client.at();

    // Assert
    assert.equal(first, vega0);
    assert.equal(second, nova1);
    assert.equal(none, nova1);
    assert.notEqual(first, nova0);
});

test('done shows only until you have looked at the agent', options, async t => {
    // Arrange
    const { hook, state, attach, panes: { nova0, nova1, vega0 } } = await server(t);
    const client = await attach(nova0);
    hook(nova0, 'working');
    hook(nova1, 'working');
    hook(vega0, 'working');

    // Act
    hook(nova0, 'done');
    hook(nova1, 'done');
    hook(vega0, 'done');

    // Assert: finished in front of you is already seen; elsewhere is not.
    assert.equal(state(nova0), '');
    assert.equal(state(nova1), 'done');
    assert.equal(state(vega0), 'done');

    // Act: visit the other window.
    await client.type('C-a', 'n');

    // Assert
    assert.equal(client.at(), nova1);
    assert.equal(state(nova1), '');
    assert.equal(state(vega0), 'done');
});

test('C-a g picks an agent with C-n/C-p and jumps to it on Enter', { ...options, skip: skip || noFzf }, async t => {
    // Arrange
    const { hook, attach, tmux, panes: { nova0, nova1, vega0 } } = await server(t);
    // Start from a plain shell window, so every agent is somewhere else.
    const shell = tmux('new-window', '-P', '-F', '#{pane_id}', '-t', 'nova', 'sh');
    const client = await attach(shell);
    hook(nova0, 'done');
    hook(nova1, 'blocked');
    hook(vega0, 'working');

    // Act: rows are blocked, working, done; C-n C-n C-p lands on working.
    await client.type('C-a', 'g');
    await delay(800);
    await client.type('C-n', 'C-n', 'C-p', 'Enter');
    await waitUntil(() => client.at() !== shell, 'the jump out of the picker');

    // Assert
    assert.equal(client.at(), vega0);

    // Act: from the top, Enter takes the longest-blocked agent.
    await client.type('C-a', 'g');
    await delay(800);
    await client.type('Enter');
    await waitUntil(() => client.at() === nova1, 'the jump to the blocked agent');

    // Assert
    assert.equal(client.at(), nova1);
});
