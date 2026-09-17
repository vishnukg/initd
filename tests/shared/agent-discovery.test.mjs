import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { processes, findAgent, sessionFile, copilotSessionFile, codexSqliteState, refresh, openFilesByPid } from '../../shared/configs/tmux/.config/tmux/tmux.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));

test('two panes in the same directory resolve their own agent, excluding subagents', () => {
    // Arrange
    const procs = [
        { pid: 10, parent: 1, agent: 'fish' }, { pid: 20, parent: 1, agent: 'fish' },
        { pid: 11, parent: 10, agent: 'codex' }, { pid: 21, parent: 20, agent: 'codex' },
        { pid: 12, parent: 11, agent: 'codex' },
    ];

    // Act
    const firstPaneAgent = findAgent(procs, 10, 'codex').pid;
    const secondPaneAgent = findAgent(procs, 20, 'codex').pid;
    const claudeInACodexPane = findAgent(procs, 20, 'claude');
    const ambiguousCodexPair = findAgent([...procs, { pid: 13, parent: 10, agent: 'codex' }], 10, 'codex');

    // Assert
    assert.equal(firstPaneAgent, 11);
    assert.equal(secondPaneAgent, 21);
    assert.equal(claudeInACodexPane, null);
    assert.equal(ambiguousCodexPair, null);
});

// Copilot CLI 1.0.83 renames its main thread, so `comm` reads "MainThread" while
// argv[0] - and so tmux's pane_current_command - still reads "copilot". Matching
// comm alone left the pane with a bare icon and no model or quota.
test('an agent that renamed its process is still found by argv[0]', () => {
    // Arrange
    const rows = [
        '   10       1 Thu Sep 10 01:35:11 2026 fish fish',
        '   11      10 Thu Sep 10 01:35:12 2026 MainThread copilot',
        '   12      10 Thu Sep 10 01:35:12 2026 codex codex --model gpt-5.6',
        '   13       1 Thu Sep 10 01:35:12 2026 node /opt/copilot/cli.js',
    ].join('\n');

    // Act
    const procs = processes(rows);

    // Assert
    assert.deepEqual(procs.map(p => [p.agent, p.command]), [
        ['fish', 'fish'], ['MainThread', 'copilot'], ['codex', 'codex'], ['node', 'cli.js'],
    ]);
    assert.equal(procs[1].start, 'Thu Sep 10 01:35:12 2026');

    // Act
    const renamedCopilot = findAgent(procs, 10, 'copilot').pid;

    // Assert
    assert.equal(renamedCopilot, 11);

    // Act
    // A renamed process must not become a wildcard for every other agent.
    const codexInTheSamePane = findAgent(procs, 10, 'codex').pid;

    // Assert
    assert.equal(codexInTheSamePane, 12);

    // Act
    const claudeNotPresent = findAgent(procs, 10, 'claude');

    // Assert
    assert.equal(claudeNotPresent, null);
});

for (const { name, agent, files, expected } of [
    { name: 'ignores unrelated files', agent: 'codex', files: 'p11\nn/tmp/rollout-a.jsonl\nn/tmp/config.toml', expected: '/tmp/rollout-a.jsonl' },
    { name: 'rejects ambiguous rollouts', agent: 'codex', files: 'n/tmp/rollout-a.jsonl\nn/tmp/rollout-b.jsonl', expected: null },
    { name: 'recognizes Copilot events', agent: 'copilot', files: 'n/tmp/session-state/abc/events.jsonl', expected: '/tmp/session-state/abc/events.jsonl' },
    { name: 'handles no open files', agent: 'codex', files: '', expected: null },
]) {
    test(`sessionFile ${name}`, () => {
        // Arrange
        const openFiles = files;

        // Act
        const transcript = sessionFile(agent, openFiles);

        // Assert
        assert.equal(transcript, expected);
    });
}

test('Copilot follows only its own process log and tracks foreground session changes', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-copilot-binding-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    fs.mkdirSync(path.join(dir, 'logs'));
    const log = path.join(dir, 'logs', 'process-123-42.log');
    const first = '11111111-1111-1111-1111-111111111111';
    const second = '22222222-2222-2222-2222-222222222222';
    const register = id => `2026-09-08T13:00:19.461Z [INFO] Registering foreground session: ${id}\n`;
    fs.writeFileSync(log, register(first));
    const openFiles = `p42\nn${log}\nn${dir}/session-store.db`;

    // Act
    const boundSession = await copilotSessionFile(openFiles, 42);
    const sessionForAnotherPid = await copilotSessionFile(openFiles, 99);

    // Assert
    assert.equal(boundSession, path.join(dir, 'session-state', first, 'events.jsonl'));
    assert.equal(sessionForAnotherPid, null);

    // Arrange
    fs.appendFileSync(log, '2026-09-08T13:00:20Z [INFO] auxiliary session: ' + second + '\n');

    // Act
    const afterAuxiliaryLine = await copilotSessionFile(openFiles, 42);

    // Assert
    assert.equal(afterAuxiliaryLine, path.join(dir, 'session-state', first, 'events.jsonl'));

    // Arrange
    fs.appendFileSync(log, register(second).slice(0, -1));

    // Act
    const afterPartialLine = await copilotSessionFile(openFiles, 42);

    // Assert
    assert.equal(afterPartialLine, path.join(dir, 'session-state', first, 'events.jsonl'));

    // Arrange
    fs.appendFileSync(log, '\n');

    // Act
    const afterCompletedLine = await copilotSessionFile(openFiles, 42);

    // Assert
    assert.equal(afterCompletedLine, path.join(dir, 'session-state', second, 'events.jsonl'));

    // Arrange
    fs.appendFileSync(log, `2026-09-08T13:00:21Z [INFO] Unregistering foreground session: ${second}\n`);

    // Act
    const afterUnregistration = await copilotSessionFile(openFiles, 42);
    const withTwoProcessLogs = await copilotSessionFile(openFiles + `\nn${dir}/logs/process-456-42.log`, 42);

    // Assert
    assert.equal(afterUnregistration, null);
    assert.equal(withTwoProcessLogs, null);
});

// Codex may not create a rollout until its first turn, so its open SQLite
// databases are the fallback. Every case below shares one fixture: two log
// databases and two state databases, where the OLDER schema of each pair holds
// the wrong answer on purpose, plus a terminal that is not a database at all.
//
// Schema numbers bump on migration, so the newest name of each pair must win.
async function codexDatabases(t) {
    const { DatabaseSync } = await import('node:sqlite');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-sqlite-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const proc = { pid: 77, parent: 1, start: 'Thu Sep 10 01:35:11 2026', agent: 'codex' };
    const started = Math.floor(Date.parse(proc.start) / 1000);
    const build = (name, statements) => {
        const db = new DatabaseSync(path.join(dir, `${name}.sqlite`));
        for (const sql of statements) db.exec(sql);
        db.close();
        return `n${path.join(dir, `${name}.sqlite`)}\n`;
    };
    const logs = 'create table logs (id integer primary key, ts integer, thread_id text, process_uuid text, feedback_log_body text)';
    const threads = 'create table threads (id text primary key, model text)';
    const rows = values => `insert into logs (id, ts, thread_id, process_uuid, feedback_log_body) values ${values}`;

    build('logs_1', [logs, rows(`(1, ${started + 5}, 'wrong-db-thread', 'pid:77:zzz', null)`)]);
    // 'turn-id' is the regression: Codex 0.154.0 stamps a turn's rows with that
    // turn's own id in the same column, so the newest row is usually NOT a
    // thread. Both ids are UUIDv7, so only the threads table separates them.
    build('logs_2', [logs, rows(`
        (1, ${started - 60}, 'reused-pid-thread', 'pid:77:aaa', null),
        (2, ${started + 10}, null, 'pid:77:bbb', null),
        (3, ${started + 20}, 'live-thread', 'pid:77:bbb', null),
        (4, ${started + 25}, 'turn-id', 'pid:77:bbb', null),
        (5, ${started + 30}, 'other-pane-thread', 'pid:88:ccc', null)`)]);
    build('state_4', [threads, "insert into threads values ('live-thread', 'wrong-db-model')"]);
    build('state_5', [threads, `insert into threads values
        ('live-thread', 'gpt-5.6-luna'), ('reused-pid-thread', 'gpt-old')`]);

    // Before its first turn there is no threads row at all, so only the
    // session_init log line names the model. Every id logged by then came from
    // thread/start, which is why the newest one is the thread's own.
    const init = "session_init: Configuring session: model=gpt-5.6-terra; provider=ConfiguredModelProvider { info:";
    build('logs_3', [logs, rows(`
        (1, ${started + 5}, 'fresh-thread', 'pid:77:ddd', '${init}'),
        (2, ${started + 6}, 'fresh-thread', 'pid:77:ddd', 'shell snapshot captured')`)]);

    const open = names => names.map(name => `n${path.join(dir, `${name}.sqlite`)}`).join('\n')
        + '\nn/dev/pts/3\n';
    return {
        proc,
        threads,
        build,
        // A session that has taken a turn: logs_2 names the thread, state_5 its model.
        started: open(['logs_1', 'logs_2', 'state_4', 'state_5']),
        // A session before its first turn: only logs_3's session_init line has a model.
        fresh: open(['logs_1', 'logs_3', 'state_4', 'state_5']),
    };
}

test('Codex takes the thread from the newest log database, ignoring turn ids', async t => {
    // Arrange
    const codex = await codexDatabases(t);

    // Act
    const state = await codexSqliteState(codex.started, codex.proc);

    // Assert
    assert.deepEqual(state, { id: 'live-thread', model: 'gpt-5.6-luna' });
});

test('a thread whose model is not recorded yet keeps the bare agent name', async t => {
    // Arrange
    // The caller shows "codex" rather than inventing a model name.
    const codex = await codexDatabases(t);
    const pending = codex.started + codex.build('state_6', [codex.threads,
        "insert into threads values ('live-thread', null)"]);

    // Act
    const state = await codexSqliteState(pending, codex.proc);

    // Assert
    assert.deepEqual(state, { id: 'live-thread', model: null });
});

test('a logged id that no threads row confirms identifies nothing', async t => {
    // Arrange
    // Every logged id being a turn is indistinguishable from knowing nothing.
    const codex = await codexDatabases(t);
    const unconfirmed = codex.started + codex.build('state_7', [codex.threads,
        "insert into threads values ('some-other-thread', 'gpt-nope')"]);

    // Act
    const state = await codexSqliteState(unconfirmed, codex.proc);

    // Assert
    assert.equal(state, null);
});

test('before its first turn the session_init log line names the model', async t => {
    // Arrange
    const codex = await codexDatabases(t);
    const withoutThreadsRow = codex.fresh + codex.build('state_7', [codex.threads,
        "insert into threads values ('some-other-thread', 'gpt-nope')"]);

    // Act
    const state = await codexSqliteState(withoutThreadsRow, codex.proc);

    // Assert
    assert.deepEqual(state, { id: 'fresh-thread', model: 'gpt-5.6-terra' });
});

test('a threads row outranks the session_init log message', async t => {
    // Arrange
    // A log message is the weakest source: a threads row names the model a
    // later /model switch left behind, so it must win over the startup line.
    const codex = await codexDatabases(t);
    const switched = codex.fresh + codex.build('state_8', [codex.threads,
        "insert into threads values ('fresh-thread', 'gpt-switched-to')"]);

    // Act
    const state = await codexSqliteState(switched, codex.proc);

    // Assert
    assert.deepEqual(state, { id: 'fresh-thread', model: 'gpt-switched-to' });
});

test('schema 10 is newer than schema 8, though alphabetic sorting says otherwise', async t => {
    // Arrange
    const codex = await codexDatabases(t);
    const both = codex.fresh
        + codex.build('state_7', [codex.threads, "insert into threads values ('some-other-thread', 'gpt-nope')"])
        + codex.build('state_8', [codex.threads, "insert into threads values ('fresh-thread', 'gpt-switched-to')"])
        + codex.build('state_10', [codex.threads, "insert into threads values ('fresh-thread', 'gpt-latest')"]);

    // Act
    const state = await codexSqliteState(both, codex.proc);

    // Assert
    assert.deepEqual(state, { id: 'fresh-thread', model: 'gpt-latest' });
});

// The kernel reuses pids, so rows that predate this process are not its own,
// and a process whose start time will not parse can never be matched at all.
for (const { name, patch, transcript } of [
    { name: 'a reused pid ignores rows recorded before it started', patch: { pid: 99 }, transcript: 'started' },
    { name: 'a reused pid learns nothing from the session_init line either', patch: { pid: 99 }, transcript: 'fresh' },
    { name: 'an unparseable process start time matches nothing', patch: { start: 'unknown' }, transcript: 'started' },
]) {
    test(`Codex SQLite fallback: ${name}`, async t => {
        // Arrange
        const codex = await codexDatabases(t);
        const openFiles = codex[transcript];

        // Act
        const state = await codexSqliteState(openFiles, { ...codex.proc, ...patch });

        // Assert
        assert.equal(state, null);
    });
}

test('a pane with no open database has no fallback to read', async t => {
    // Arrange
    // Only a terminal is open: nothing here is a Codex database.
    const codex = await codexDatabases(t);

    // Act
    const state = await codexSqliteState('n/dev/pts/3\n', codex.proc);

    // Assert
    assert.equal(state, null);
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

test('one asynchronous lsof scan covers all agents and does not delay Claude', async () => {
    // Arrange
    const writes = [];
    const calls = [];
    let release;
    const lookup = new Promise(resolve => { release = resolve; });

    // Act
    const pending = refresh({
        run(command, args) {
            calls.push([command, args]);
            return command === 'tmux' ? '%1\t1\t10\tcodex\t/repo\t1\n%2\t1\t20\tcopilot\t/repo\t0\n%3\t1\t30\tclaude\t/repo\t0' : lookup;
        },
        processes: async () => [
            { pid: 10, parent: 1, agent: 'codex' },
            { pid: 20, parent: 1, agent: 'copilot' },
            { pid: 30, parent: 1, agent: 'claude' },
        ],
        atomic: (file, value) => writes.push([file, value]),
    });

    await new Promise(resolve => setImmediate(resolve));

    // Assert
    assert.equal(writes.length, 1);
    assert.match(writes[0][1], /\nclaude\n/);
    assert.deepEqual(calls.filter(c => c[0] === 'lsof'), [['lsof', ['-a', '-p', '10,20', '-Fn']]]);

    // Arrange
    release('');
    // timeout/unavailable lookup still emits safe icon-only caches
    await pending;

    // Assert
    assert.equal(writes.length, 3);

    // Act
    const files = openFilesByPid('nignored\np10\nn/tmp/rollout-one.jsonl\np20\nn/tmp/session-state/two/events.jsonl\n');
    const codexTranscript = sessionFile('codex', files.get(10));

    // Assert
    assert.equal(codexTranscript, '/tmp/rollout-one.jsonl');

    // Act
    const copilotTranscript = sessionFile('copilot', files.get(20));

    // Assert
    assert.equal(copilotTranscript, '/tmp/session-state/two/events.jsonl');
    assert.equal(files.size, 2);
});

// The Claude status line runs claude-statusline-hook.mjs as its own process, so
// the hook is exercised the same way: a real subprocess, a fake `ps` on PATH and
// a temporary HOME. Its own ppid is this test file's pid, which is what the fake
// process table is built around.
function hookFixture(t, rows) {
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
        cache: pid => path.join(home, '.cache/initd-tmux', `claude-${pid}.json`),
        cached: () => {
            try { return fs.readdirSync(path.join(home, '.cache/initd-tmux')); }
            catch { return []; }
        },
        run: data => spawnSync(process.execPath,
            [path.join(root, 'shared/configs/tmux/.config/tmux/claude-statusline-hook.mjs')], {
                input: JSON.stringify(data), env: { HOME: home, PATH: bin },
                encoding: 'utf8', timeout: 10000,
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

// Every other refresh test hands in a snapshot, which skips the list-panes
// parse entirely. tmux emits one tab-separated row per pane, and a pane whose
// path or command contains a tab would otherwise shift every later field.
test('malformed list-panes rows are dropped rather than published against', async () => {
    // Arrange
    const writes = [];
    const rows = [
        '%1\t1\t10\tcodex\t/repo\t1',
        // Six fields but not a pane id: never a target for set-option -t.
        'x1\t1\t11\tcodex\t/repo\t1',
        // A tab inside the pane path splits the row into seven fields.
        '%2\t1\t12\tcodex\t/re\tpo\t1',
        // Truncated row: tmux was killed mid-write.
        '%3\t1\t13\tcodex',
        '',
    ].join('\n');

    // Act
    await refresh({
        run: async () => rows,
        processes: async () => [
            { pid: 10, parent: 1, agent: 'codex' }, { pid: 11, parent: 1, agent: 'codex' },
            { pid: 12, parent: 1, agent: 'codex' }, { pid: 13, parent: 1, agent: 'codex' },
        ],
        atomic: file => writes.push(path.basename(file)),
    });

    // Assert
    assert.deepEqual(writes, ['pane-1-10']);
});
