import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { processes, findAgent, refresh } from '../../shared/configs/tmux/.config/tmux/tmux.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));

test('two panes in the same directory resolve their own agent, excluding subagents', () => {
    // Arrange
    const procs = [
        { pid: 10, parent: 1, agent: 'fish' }, { pid: 20, parent: 1, agent: 'fish' },
        { pid: 11, parent: 10, agent: 'claude' }, { pid: 21, parent: 20, agent: 'claude' },
        { pid: 12, parent: 11, agent: 'claude' },
    ];

    // Act
    const firstPaneAgent = findAgent(procs, 10, 'claude').pid;
    const secondPaneAgent = findAgent(procs, 20, 'claude').pid;
    const nvimNotPresent = findAgent(procs, 20, 'nvim');
    const ambiguousClaudePair = findAgent([...procs, { pid: 13, parent: 10, agent: 'claude' }], 10, 'claude');

    // Assert
    assert.equal(firstPaneAgent, 11);
    assert.equal(secondPaneAgent, 21);
    assert.equal(nvimNotPresent, null);
    assert.equal(ambiguousClaudePair, null);
});

// A process may rename its main thread, so `comm` reads e.g. "MainThread" while
// argv[0] - and so tmux's pane_current_command - still reads the agent's name.
// Matching comm alone would leave the pane with a bare icon and no model or quota.
test('an agent that renamed its process is still found by argv[0]', () => {
    // Arrange
    const rows = [
        '   10       1 Thu Sep 10 01:35:11 2026 fish fish',
        '   11      10 Thu Sep 10 01:35:12 2026 MainThread claude',
        '   12      10 Thu Sep 10 01:35:12 2026 nvim nvim README.md',
        '   13       1 Thu Sep 10 01:35:12 2026 node /opt/claude/cli.js',
    ].join('\n');

    // Act
    const procs = processes(rows);

    // Assert
    assert.deepEqual(procs.map(p => [p.agent, p.command]), [
        ['fish', 'fish'], ['MainThread', 'claude'], ['nvim', 'nvim'], ['node', 'cli.js'],
    ]);
    assert.equal(procs[1].start, 'Thu Sep 10 01:35:12 2026');

    // Act
    const renamedClaude = findAgent(procs, 10, 'claude').pid;

    // Assert
    assert.equal(renamedClaude, 11);

    // Act
    // A renamed process must not become a wildcard for every other command.
    const nvimInTheSamePane = findAgent(procs, 10, 'nvim').pid;

    // Assert
    assert.equal(nvimInTheSamePane, 12);
});

test('idle watcher skips process scans and all expensive data work', async () => {
    // Arrange
    const calls = [];

    // Act
    await refresh({
        run: (command, args) => { calls.push([command, args[0]]); return '%1\t1\t2\tfish\t/repo\t1\n%2\t1\t3\tnvim\t/repo\t0\n'; },
        processes: () => { throw new Error('idle process scan'); },
    });

    // Assert
    assert.deepEqual(calls, [['tmux', 'list-panes']]);
});

// The Claude status line runs claude-statusline-hook.mjs as its own process, so
// the hook is exercised the same way: a real subprocess, a fake `ps` on PATH and
// a temporary HOME. Its own ppid is this test file's pid, which is what the fake
// process table is built around.
function hookFixture(t, rows, agent = 'claude') {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-hook-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    const bin = path.join(home, 'bin');
    fs.mkdirSync(bin);
    const table = rows.map(([pid, parent, name]) =>
        `${pid} ${parent} Thu Sep 10 01:35:11 2026 ${name} ${name}`).join('\n');
    // PATH holds nothing but this directory, so the real `ps` can never answer
    // instead - which also means the fake may only use shell builtins.
    fs.writeFileSync(path.join(bin, 'ps'), `#!/bin/sh\necho '${table}'\n`, { mode: 0o755 });
    return {
        home,
        cache: pid => path.join(home, '.cache/initd-tmux', `${agent}-${pid}.json`),
        cached: () => {
            try { return fs.readdirSync(path.join(home, '.cache/initd-tmux')); }
            catch { return []; }
        },
        run: data => spawnSync(process.execPath,
            [path.join(root, `shared/configs/tmux/.config/tmux/${agent}-statusline-hook.mjs`)], {
                // The hook's own command limit is 3s; a busy parallel suite can
                // exceed that for even this fake ps, so both get headroom.
                input: JSON.stringify(data), env: { HOME: home, PATH: bin, INITD_COMMAND_TIMEOUT_MS: '15000' },
                encoding: 'utf8', timeout: 30000,
            }),
    };
}

test('the Claude hook caches its own agent process and appends the context window', t => {
    // Arrange
    const claudePid = 424242;
    const hook = hookFixture(t, [
        [process.pid, claudePid, 'node'],
        [claudePid, 1, 'claude'],
        // A second, unrelated Claude must not be picked up in place of the parent.
        [999999, 1, 'claude'],
    ]);
    // The hook reads the real clock, so the reset is anchored to it: a fixed
    // far-future timestamp would render in the days form instead.
    const rateLimits = { five_hour: { used_percentage: 30, resets_at: Math.floor(Date.now() / 1000) + 7200 } };

    // Act
    const result = hook.run({
        model: { display_name: 'Opus 5' },
        rate_limits: rateLimits,
        context_window: { used_percentage: 42.4 },
    });

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /^Opus 5 · 30% · \d+h\d+m · 42% ctx$/);
    assert.deepEqual(hook.cached(), [`claude-${claudePid}.json`]);
    assert.deepEqual(JSON.parse(fs.readFileSync(hook.cache(claudePid), 'utf8')), {
        start: 'Thu Sep 10 01:35:11 2026',
        data: { model: { display_name: 'Opus 5' }, rate_limits: rateLimits },
    });
});

test('the agy hook caches its own process, keeping the quota map with its absolute reset times', t => {
    // Arrange
    const agyPid = 424244;
    const hook = hookFixture(t, [
        [process.pid, agyPid, 'node'],
        [agyPid, 1, 'agy'],
        // A Claude higher up the tree is not this hook's agent.
        [1, 0, 'claude'],
    ], 'agy');
    const quota = { 'gemini-5h': {
        remaining_fraction: 0.7, reset_in_seconds: 7200,
        reset_time: new Date(Date.now() + 7200 * 1000).toISOString(),
    } };
    const model = { id: 'Gemini 3.8 Flash (Medium)', display_name: 'Gemini 3.8 Flash (Medium)' };

    // Act
    const result = hook.run({ model, quota, context_window: { used_percentage: 2.4 }, cwd: '/repo' });

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /^Gemini 3\.8 Flash \(Medium\) · 30% · \d+h\d+m · 2% ctx$/);
    assert.deepEqual(hook.cached(), [`agy-${agyPid}.json`]);
    assert.deepEqual(JSON.parse(fs.readFileSync(hook.cache(agyPid), 'utf8')), {
        start: 'Thu Sep 10 01:35:11 2026', data: { model, quota },
    });
});

test('the Claude hook omits an absent context window and caches no unknown ancestry', t => {
    // Arrange
    const claudePid = 424243;
    const named = hookFixture(t, [[process.pid, claudePid, 'node'], [claudePid, 1, 'claude']]);

    // Act
    const withoutContext = named.run({ model: { display_name: 'Opus 5' } });

    // Assert
    assert.equal(withoutContext.stdout, 'Opus 5');

    // Arrange
    // Nothing in the ancestry is Claude: the value still prints, but a cache
    // entry keyed to the wrong process would outlive this run and mislabel a pane.
    const orphaned = hookFixture(t, [[process.pid, 1, 'node']]);

    // Act
    const unowned = orphaned.run({ model: { display_name: 'Opus 5' } });

    // Assert
    assert.equal(unowned.status, 0, unowned.stderr);
    assert.equal(unowned.stdout, 'Opus 5');
    assert.deepEqual(orphaned.cached(), []);
});

test('the Claude hook terminates on a cyclic process table instead of hanging', t => {
    // Arrange
    // A pid whose ancestry loops back on itself: without the seen-set guard the
    // walk never ends, and the status line blocks Claude's own render.
    const hook = hookFixture(t, [
        [process.pid, 500, 'node'], [500, 501, 'fish'], [501, 500, 'fish'],
    ]);

    // Act
    const result = hook.run({ model: { display_name: 'Opus 5' } });

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.signal, null, 'a timed-out hook is killed by signal');
    assert.equal(result.stdout, 'Opus 5');
    assert.deepEqual(hook.cached(), []);
});

test('refresh renders each agent from its own hook cache, never the other agent\'s', async t => {
    // Arrange
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-refresh-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    const script = path.join(root, 'shared/configs/tmux/.config/tmux/tmux.mjs');
    const start = 'Thu Sep 10 01:35:11 2026';
    const cache = path.join(home, '.cache/initd-tmux');
    fs.mkdirSync(cache, { recursive: true });
    fs.writeFileSync(path.join(cache, 'agy-11.json'), JSON.stringify({ start, data: { model: { display_name: 'Gemini Pro' } } }));
    // Same pid under the other agent's name: must not be read for the agy pane.
    fs.writeFileSync(path.join(cache, 'claude-11.json'), JSON.stringify({ start, data: { model: { display_name: 'Opus 5' } } }));
    // tmux.mjs fixes its cache directory from HOME at load, so it runs in a
    // child with the temporary HOME rather than being imported here.
    const program = `
        const { refresh } = await import(${JSON.stringify(script)});
        const writes = [];
        await refresh({
            run: async () => '',
            processes: async () => [{ pid: 11, parent: 10, agent: 'agy', start: ${JSON.stringify(start)} }],
            atomic: (file, value) => writes.push(value),
        }, [['%1', '1', '10', 'agy', '/repo', '1'], ['%2', '1', '20', 'agy', '/repo', '0']]);
        process.stdout.write(JSON.stringify(writes));`;

    // Act
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', program], {
        env: { ...process.env, HOME: home }, encoding: 'utf8',
    });

    // Assert
    assert.equal(result.status, 0, result.stderr);
    const writes = JSON.parse(result.stdout).map(value => value.split('\n').slice(1, 3));
    assert.deepEqual(writes.sort(), [['agy', 'Gemini Pro'], ['agy', 'agy']]);
});

// Every other refresh test hands in a snapshot, which skips the list-panes
// parse entirely. tmux emits one tab-separated row per pane, and a pane whose
// path or command contains a tab would otherwise shift every later field.
test('malformed list-panes rows are dropped rather than published against', async () => {
    // Arrange
    const writes = [];
    const rows = [
        '%1\t1\t10\tclaude\t/repo\t1',
        // Six fields but not a pane id: never a target for set-option -t.
        'x1\t1\t11\tclaude\t/repo\t1',
        // A tab inside the pane path splits the row into seven fields.
        '%2\t1\t12\tclaude\t/re\tpo\t1',
        // Truncated row: tmux was killed mid-write.
        '%3\t1\t13\tclaude',
        '',
    ].join('\n');

    // Act
    await refresh({
        run: async () => rows,
        processes: async () => [
            { pid: 10, parent: 1, agent: 'claude' }, { pid: 11, parent: 1, agent: 'claude' },
            { pid: 12, parent: 1, agent: 'claude' }, { pid: 13, parent: 1, agent: 'claude' },
        ],
        atomic: file => writes.push(path.basename(file)),
    });

    // Assert
    assert.deepEqual(writes, ['pane-1-10']);
});
