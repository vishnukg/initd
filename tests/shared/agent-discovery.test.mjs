import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { processes, findAgent, sessionFile, copilotSessionFile, codexSqliteState, refresh, openFilesByPid } from '../../shared/configs/tmux/.config/tmux/tmux.mjs';

test('two panes in the same directory resolve their own agent, excluding subagents', () => {
    // Arrange
    const procs = [
        { pid: 10, parent: 1, agent: 'fish' }, { pid: 20, parent: 1, agent: 'fish' },
        { pid: 11, parent: 10, agent: 'codex' }, { pid: 21, parent: 20, agent: 'codex' },
        { pid: 12, parent: 11, agent: 'codex' },
    ];

    // Act
    const findAgentResult = findAgent(procs, 10, 'codex').pid;
    const findAgentResult2 = findAgent(procs, 20, 'codex').pid;
    const findAgentResult3 = findAgent(procs, 20, 'claude');
    const findAgentResult4 = findAgent([...procs, { pid: 13, parent: 10, agent: 'codex' }], 10, 'codex');

    // Assert
    assert.equal(findAgentResult, 11);
    assert.equal(findAgentResult2, 21);
    assert.equal(findAgentResult3, null);
    assert.equal(findAgentResult4, null);
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
    const findAgentResult = findAgent(procs, 10, 'copilot').pid;

    // Assert
    assert.equal(findAgentResult, 11);

    // Act
    // A renamed process must not become a wildcard for every other agent.
    const findAgentResult2 = findAgent(procs, 10, 'codex').pid;

    // Assert
    assert.equal(findAgentResult2, 12);

    // Act
    const findAgentResult3 = findAgent(procs, 10, 'claude');

    // Assert
    assert.equal(findAgentResult3, null);
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
    const copilotSessionFileResult = await copilotSessionFile(openFiles, 42);
    const copilotSessionFileResult2 = await copilotSessionFile(openFiles, 99);

    // Assert
    assert.equal(copilotSessionFileResult, path.join(dir, 'session-state', first, 'events.jsonl'));
    assert.equal(copilotSessionFileResult2, null);

    // Arrange
    fs.appendFileSync(log, '2026-09-08T13:00:20Z [INFO] auxiliary session: ' + second + '\n');

    // Act
    const copilotSessionFileResult3 = await copilotSessionFile(openFiles, 42);

    // Assert
    assert.equal(copilotSessionFileResult3, path.join(dir, 'session-state', first, 'events.jsonl'));

    // Arrange
    fs.appendFileSync(log, register(second).slice(0, -1));

    // Act
    const copilotSessionFileResult4 = await copilotSessionFile(openFiles, 42);

    // Assert
    assert.equal(copilotSessionFileResult4, path.join(dir, 'session-state', first, 'events.jsonl'));

    // Arrange
    fs.appendFileSync(log, '\n');

    // Act
    const copilotSessionFileResult5 = await copilotSessionFile(openFiles, 42);

    // Assert
    assert.equal(copilotSessionFileResult5, path.join(dir, 'session-state', second, 'events.jsonl'));

    // Arrange
    fs.appendFileSync(log, `2026-09-08T13:00:21Z [INFO] Unregistering foreground session: ${second}\n`);

    // Act
    const copilotSessionFileResult6 = await copilotSessionFile(openFiles, 42);
    const copilotSessionFileResult7 = await copilotSessionFile(openFiles + `\nn${dir}/logs/process-456-42.log`, 42);

    // Assert
    assert.equal(copilotSessionFileResult6, null);
    assert.equal(copilotSessionFileResult7, null);
});

test('Codex falls back to its SQLite state when no rollout file is open', async t => {
    // Arrange
    const { DatabaseSync } = await import('node:sqlite');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-sqlite-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const proc = { pid: 77, parent: 1, start: 'Thu Sep 10 01:35:11 2026', agent: 'codex' };
    const started = Math.floor(Date.parse(proc.start) / 1000);
    // Schema versions bump on migration, so the newest name of each pair wins:
    // the older databases hold the wrong answer on purpose.
    const build = (name, statements) => {
        const db = new DatabaseSync(path.join(dir, `${name}.sqlite`));
        for (const sql of statements) db.exec(sql);
        db.close();
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
    const openFiles = ['logs_1', 'logs_2', 'state_4', 'state_5']
        .map(name => `n${path.join(dir, `${name}.sqlite`)}`).join('\n') + '\nn/dev/pts/3\n';

    // Act
    const codexSqliteStateResult = await codexSqliteState(openFiles, proc);

    // Assert
    assert.deepEqual(codexSqliteStateResult, { id: 'live-thread', model: 'gpt-5.6-luna' });

    // Act
    // The kernel reuses pids, so a row predating this process is not ours.
    const codexSqliteStateResult2 = await codexSqliteState(openFiles, { ...proc, pid: 99 });

    // Assert
    assert.equal(codexSqliteStateResult2, null);

    // Act
    const codexSqliteStateResult3 = await codexSqliteState('n/dev/pts/3\n', proc);

    // Assert
    assert.equal(codexSqliteStateResult3, null);

    // Arrange
    // A thread whose model column is not set yet: the caller keeps the bare
    // agent name rather than inventing one.
    build('state_6', [threads, "insert into threads values ('live-thread', null)"]);
    const pending = openFiles + `n${path.join(dir, 'state_6.sqlite')}\n`;

    // Act
    const codexSqliteStateResult4 = await codexSqliteState(pending, proc);

    // Assert
    assert.deepEqual(codexSqliteStateResult4, { id: 'live-thread', model: null });

    // Arrange
    // Every logged id being a turn is indistinguishable from knowing nothing.
    build('state_7', [threads, "insert into threads values ('some-other-thread', 'gpt-nope')"]);

    // Act
    const codexSqliteStateResult5 = await codexSqliteState(openFiles + `n${path.join(dir, 'state_7.sqlite')}\n`, proc);

    // Assert
    assert.equal(codexSqliteStateResult5, null);

    // Arrange
    // Before its first turn there is no threads row at all, so only the
    // session_init log line names the model. Every id logged by then came from
    // thread/start, which is why the newest one is the thread's own.
    const init = "session_init: Configuring session: model=gpt-5.6-terra; provider=ConfiguredModelProvider { info:";
    build('logs_3', [logs, rows(`
        (1, ${started + 5}, 'fresh-thread', 'pid:77:ddd', '${init}'),
        (2, ${started + 6}, 'fresh-thread', 'pid:77:ddd', 'shell snapshot captured')`)]);
    const state7 = `n${path.join(dir, 'state_7.sqlite')}\n`;
    const logs3 = ['logs_1', 'logs_3', 'state_4', 'state_5']
        .map(name => `n${path.join(dir, `${name}.sqlite`)}`).join('\n') + '\n';

    // Act
    const codexSqliteStateResult6 = await codexSqliteState(logs3 + state7, proc);

    // Assert
    assert.deepEqual(codexSqliteStateResult6, { id: 'fresh-thread', model: 'gpt-5.6-terra' });

    // Arrange
    // A log message is the weakest source: a threads row that names a model, and
    // so survives a later /model switch, must win over it.
    build('state_8', [threads, "insert into threads values ('fresh-thread', 'gpt-switched-to')"]);

    // Act
    const codexSqliteStateResult7 = await codexSqliteState(logs3 + `n${path.join(dir, 'state_8.sqlite')}\n`, proc);

    // Assert
    assert.deepEqual(codexSqliteStateResult7,
        { id: 'fresh-thread', model: 'gpt-switched-to' });

    // Act
    // A pid whose rows predate it learns nothing from the log line either.
    const codexSqliteStateResult8 = await codexSqliteState(logs3 + state7, { ...proc, pid: 99 });

    // Assert
    assert.equal(codexSqliteStateResult8, null);

    // Act
    const codexSqliteStateResult9 = await codexSqliteState(openFiles, { ...proc, start: 'unknown' });

    // Assert
    assert.equal(codexSqliteStateResult9, null);

    // Arrange
    // Schema 10 is newer than 8, even though alphabetic sorting says otherwise.
    build('state_10', [threads, "insert into threads values ('fresh-thread', 'gpt-latest')"]);

    // Act
    const codexSqliteStateResult10 = await codexSqliteState(logs3 + state7
        + `n${path.join(dir, 'state_10.sqlite')}\n`, proc);

    // Assert
    assert.deepEqual(codexSqliteStateResult10,
    { id: 'fresh-thread', model: 'gpt-latest' });
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
    const sessionFileResult = sessionFile('codex', files.get(10));

    // Assert
    assert.equal(sessionFileResult, '/tmp/rollout-one.jsonl');

    // Act
    const sessionFileResult2 = sessionFile('copilot', files.get(20));

    // Assert
    assert.equal(sessionFileResult2, '/tmp/session-state/two/events.jsonl');
    assert.equal(files.size, 2);
});
