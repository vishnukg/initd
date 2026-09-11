import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { processes, findAgent, sessionFile, copilotSessionFile, sessionState, claudeValue, codexUsage, codexLimit, codexSqliteState, modelName, refresh, openFilesByPid, createStatusPublisher } from './configs/tmux/.config/tmux/tmux.mjs';
const helper = fileURLToPath(new URL('./configs/tmux/.config/tmux/tmux.mjs', import.meta.url));

test('two panes in the same directory resolve their own agent, excluding subagents', () => {
    const procs = [
        { pid: 10, parent: 1, agent: 'fish' }, { pid: 20, parent: 1, agent: 'fish' },
        { pid: 11, parent: 10, agent: 'codex' }, { pid: 21, parent: 20, agent: 'codex' },
        { pid: 12, parent: 11, agent: 'codex' },
    ];
    assert.equal(findAgent(procs, 10, 'codex').pid, 11);
    assert.equal(findAgent(procs, 20, 'codex').pid, 21);
    assert.equal(findAgent(procs, 20, 'claude'), null);
    assert.equal(findAgent([...procs, { pid: 13, parent: 10, agent: 'codex' }], 10, 'codex'), null);
});

// Copilot CLI 1.0.83 renames its main thread, so `comm` reads "MainThread" while
// argv[0] - and so tmux's pane_current_command - still reads "copilot". Matching
// comm alone left the pane with a bare icon and no model or quota.
test('an agent that renamed its process is still found by argv[0]', () => {
    const rows = [
        '   10       1 Thu Sep 10 01:35:11 2026 fish fish',
        '   11      10 Thu Sep 10 01:35:12 2026 MainThread copilot',
        '   12      10 Thu Sep 10 01:35:12 2026 codex codex --model gpt-5.6',
        '   13       1 Thu Sep 10 01:35:12 2026 node /opt/copilot/cli.js',
    ].join('\n');
    const procs = processes(rows);
    assert.deepEqual(procs.map(p => [p.agent, p.command]), [
        ['fish', 'fish'], ['MainThread', 'copilot'], ['codex', 'codex'], ['node', 'cli.js'],
    ]);
    assert.equal(procs[1].start, 'Thu Sep 10 01:35:12 2026');
    assert.equal(findAgent(procs, 10, 'copilot').pid, 11);
    // A renamed process must not become a wildcard for every other agent.
    assert.equal(findAgent(procs, 10, 'codex').pid, 12);
    assert.equal(findAgent(procs, 10, 'claude'), null);
});
test('open-file binding rejects ambiguous transcripts and ignores other files', () => {
    assert.equal(sessionFile('codex', 'p11\nn/tmp/rollout-a.jsonl\nn/tmp/config.toml'), '/tmp/rollout-a.jsonl');
    assert.equal(sessionFile('codex', 'n/tmp/rollout-a.jsonl\nn/tmp/rollout-b.jsonl'), null);
    assert.equal(sessionFile('copilot', 'n/tmp/session-state/abc/events.jsonl'), '/tmp/session-state/abc/events.jsonl');
    assert.equal(sessionFile('codex', ''), null);
});
test('Copilot follows only its own process log and tracks foreground session changes', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-copilot-binding-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    fs.mkdirSync(path.join(dir, 'logs'));
    const log = path.join(dir, 'logs', 'process-123-42.log');
    const first = '11111111-1111-1111-1111-111111111111';
    const second = '22222222-2222-2222-2222-222222222222';
    const register = id => `2026-09-08T13:00:19.461Z [INFO] Registering foreground session: ${id}\n`;
    fs.writeFileSync(log, register(first));
    const openFiles = `p42\nn${log}\nn${dir}/session-store.db`;
    assert.equal(await copilotSessionFile(openFiles, 42), path.join(dir, 'session-state', first, 'events.jsonl'));
    assert.equal(await copilotSessionFile(openFiles, 99), null);
    fs.appendFileSync(log, '2026-09-08T13:00:20Z [INFO] auxiliary session: ' + second + '\n');
    assert.equal(await copilotSessionFile(openFiles, 42), path.join(dir, 'session-state', first, 'events.jsonl'));
    fs.appendFileSync(log, register(second).slice(0, -1));
    assert.equal(await copilotSessionFile(openFiles, 42), path.join(dir, 'session-state', first, 'events.jsonl'));
    fs.appendFileSync(log, '\n');
    assert.equal(await copilotSessionFile(openFiles, 42), path.join(dir, 'session-state', second, 'events.jsonl'));
    fs.appendFileSync(log, `2026-09-08T13:00:21Z [INFO] Unregistering foreground session: ${second}\n`);
    assert.equal(await copilotSessionFile(openFiles, 42), null);
    assert.equal(await copilotSessionFile(openFiles + `\nn${dir}/logs/process-456-42.log`, 42), null);
});
test('model switches use the latest context, not historical usage or auxiliary calls', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-test-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-a.jsonl');
    fs.writeFileSync(file, [
        { type: 'turn_context', payload: { model: 'old-model' } },
        { type: 'turn_context', payload: { model: 'new-model' } },
        { type: 'event_msg', payload: { model: 'old-model' } },
    ].map(record => JSON.stringify(record)).join('\n') + '\n{"partial":');
    assert.deepEqual(await sessionState('codex', file), { id: 'rollout-a', model: 'new-model' });
    fs.writeFileSync(file, [
        { type: 'session.model_change', data: { newModel: 'chosen-model' } },
        { type: 'model.turn_started', data: { model: 'auxiliary-model' } },
        { type: 'session.model_change', data: { newModel: 'auto' } },
    ].map(record => JSON.stringify(record)).join('\n') + '\n');
    assert.equal((await sessionState('copilot', file)).model, 'auto');
});
test('Codex reads the latest account quota snapshot, ignoring unrelated limits and partial writes', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-quota-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-quota.jsonl');
    const latest = { limit_id: 'codex', primary: { used_percent: 31, window_minutes: 300, resets_at: 20000 } };
    const event = rate_limits => ({ type: 'event_msg', payload: { type: 'token_count', rate_limits } });
    fs.writeFileSync(file, [event({ ...latest, primary: { used_percent: 20 } }), event(latest),
        event({ limit_id: 'other-model', primary: { used_percent: 99 } }), event(null),
    ].map(record => JSON.stringify(record)).join('\n') + '\n{"partial":');
    assert.deepEqual((await sessionState('codex', file)).rateLimits, latest);
    assert.equal((await sessionState('codex', file)).rateLimits.primary.used_percent, 31);
});
test('Codex account limits are taken under either id, and a per-model one is ignored', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-limitid-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-limit.jsonl');
    const event = rate_limits => JSON.stringify({ type: 'event_msg', payload: { type: 'token_count', rate_limits } });
    const premium = { limit_id: 'premium', primary: { used_percent: 42, resets_at: 20000 } };
    // Codex renamed the account limit to "premium"; a per-model id must not win.
    fs.writeFileSync(file, [event({ limit_id: 'codex', primary: { used_percent: 7 } }), event(premium),
        event({ limit_id: 'other-model', primary: { used_percent: 99 } })].join('\n') + '\n');
    assert.deepEqual((await sessionState('codex', file)).rateLimits, premium);
    assert.equal(codexUsage(premium, 5600), ' · 42% · 4h0m');
    // The payload Codex actually sends today carries no usage at all.
    const empty = { limit_id: 'premium', primary: null, secondary: null, credits: { has_credits: false, balance: '0' } };
    assert.equal(codexUsage(empty), '');
});
test('Codex percentage includes zero, ticks down on cached data, and hides expired or invalid quota', () => {
    const limits = { primary: { used_percent: 31, resets_at: 20000 } };
    assert.equal(codexUsage(limits, 5600), ' · 31% · 4h0m');
    assert.equal(codexUsage(limits, 5660), ' · 31% · 3h59m');
    assert.equal(codexUsage(limits, 20000), '');
    assert.equal(codexUsage({ primary: { used_percent: 0 } }, 0), ' · 0%');
    assert.equal(codexUsage(null), '');
    assert.equal(codexUsage({ primary: { used_percent: '31' } }), '');
    assert.equal(codexUsage({ primary: { used_percent: -1 } }), '');
});
test('a model switched between turns is reported at once, not one turn late', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-switch-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-switch.jsonl');
    const turn = model => JSON.stringify({ type: 'turn_context', payload: { model } });
    const applied = model => JSON.stringify({
        type: 'event_msg', payload: { type: 'thread_settings_applied', thread_settings: { model } },
    });
    // A switch after the last turn wins; the next turn then confirms it.
    fs.writeFileSync(file, [turn('gpt-old'), applied('gpt-new')].join('\n') + '\n');
    assert.equal((await sessionState('codex', file)).model, 'gpt-new');
    fs.appendFileSync(file, turn('gpt-new') + '\n');
    assert.equal((await sessionState('codex', file)).model, 'gpt-new');
    // Settings carrying no model must not blank a model already known.
    fs.appendFileSync(file, JSON.stringify({
        type: 'event_msg', payload: { type: 'thread_settings_applied', thread_settings: {} },
    }) + '\n');
    assert.equal((await sessionState('codex', file)).model, 'gpt-new');
});
test('an exhausted Codex account says so, and any later turn clears it', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-exhausted-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-exhausted.jsonl');
    const complete = error => JSON.stringify({ type: 'event_msg', payload: { type: 'task_complete', error } });
    const message = "You've hit your usage limit. Upgrade to Plus to continue using Codex "
        + '(https://chatgpt.com/explore/plus), or try again at Sep 13th, 2026 6:05 PM.';
    fs.writeFileSync(file, complete({ message, codex_error_info: 'usage_limit_exceeded' }) + '\n');
    assert.equal((await sessionState('codex', file)).limit, message);
    const reset = Date.parse('Sep 13, 2026 6:05 PM') / 1000;
    assert.equal(codexLimit(message, reset - 3 * 86400 - 16 * 3600), ' · limit · 3d16h');
    assert.equal(codexLimit(message, reset - 90 * 60), ' · limit · 1h30m');
    // Once the reset has passed the countdown is gone, but the turn still failed.
    assert.equal(codexLimit(message, reset), ' · limit');
    assert.equal(codexLimit('out of quota, no date here'), ' · limit');
    assert.equal(codexLimit(null), '');
    // A turn that runs at all clears the notice without waiting for the reset.
    fs.appendFileSync(file, complete(null) + '\n');
    assert.equal((await sessionState('codex', file)).limit, null);
});
test('Codex falls back to its SQLite state when no rollout file is open', async t => {
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
    assert.deepEqual(await codexSqliteState(openFiles, proc), { id: 'live-thread', model: 'gpt-5.6-luna' });
    // The kernel reuses pids, so a row predating this process is not ours.
    assert.equal(await codexSqliteState(openFiles, { ...proc, pid: 99 }), null);
    assert.equal(await codexSqliteState('n/dev/pts/3\n', proc), null);
    // A thread whose model column is not set yet: the caller keeps the bare
    // agent name rather than inventing one.
    build('state_6', [threads, "insert into threads values ('live-thread', null)"]);
    const pending = openFiles + `n${path.join(dir, 'state_6.sqlite')}\n`;
    assert.deepEqual(await codexSqliteState(pending, proc), { id: 'live-thread', model: null });
    // Every logged id being a turn is indistinguishable from knowing nothing.
    build('state_7', [threads, "insert into threads values ('some-other-thread', 'gpt-nope')"]);
    assert.equal(await codexSqliteState(openFiles + `n${path.join(dir, 'state_7.sqlite')}\n`, proc), null);
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
    assert.deepEqual(await codexSqliteState(logs3 + state7, proc), { id: 'fresh-thread', model: 'gpt-5.6-terra' });
    // A log message is the weakest source: a threads row that names a model, and
    // so survives a later /model switch, must win over it.
    build('state_8', [threads, "insert into threads values ('fresh-thread', 'gpt-switched-to')"]);
    assert.deepEqual(await codexSqliteState(logs3 + `n${path.join(dir, 'state_8.sqlite')}\n`, proc),
        { id: 'fresh-thread', model: 'gpt-switched-to' });
    // A pid whose rows predate it learns nothing from the log line either.
    assert.equal(await codexSqliteState(logs3 + state7, { ...proc, pid: 99 }), null);
});
test('Claude can show its model without rate limits and strips tmux formatting', () => {
    assert.equal(claudeValue({ model: { display_name: 'Sonnet' } }), 'Sonnet');
    assert.equal(claudeValue({ model: { display_name: '#[bg=red]\nSonnet' } }), '[bg=red]Sonnet');
});
test('Claude holds the 5h window and escalates only to a slower one that is binding', () => {
    const model = { display_name: 'Opus 5' };
    const five = (used, resets_at = 20000) => ({ used_percentage: used, resets_at });
    const week = (used, resets_at = 200000) => ({ used_percentage: used, resets_at });
    const value = rate_limits => claudeValue({ model, rate_limits }, 5600);
    // Near-tied windows must not swap the readout back and forth: a week at 21%
    // is not yet binding, so the 5h window keeps the slot.
    assert.equal(value({ five_hour: five(19), seven_day: week(21) }), 'Opus 5 · 19% · 4h0m');
    // Past the threshold and the fuller of the two, the week takes the slot - the
    // case the original first-listed rule could never show at all.
    assert.equal(value({ five_hour: five(7), seven_day: week(62) }), 'Opus 5 · 62% week · 2d6h');
    // A 5h window about to stop the next turn is never hidden behind it.
    assert.equal(value({ five_hour: five(95), seven_day: week(62) }), 'Opus 5 · 95% · 4h0m');
    // A budget escalates on the same rule and carries its own label.
    assert.equal(value({ spend_limit: five(88), five_hour: five(19), seven_day: week(21) }), 'Opus 5 · 88% budget · 4h0m');
    // A quiet budget stays out of the way, exactly as a quiet week does.
    assert.equal(value({ spend_limit: five(30), five_hour: five(19) }), 'Opus 5 · 19% · 4h0m');
    // With no 5h window to hold the slot, a slower one below the threshold is
    // still reported rather than leaving the pill with only a model name.
    assert.equal(value({ seven_day: week(21) }), 'Opus 5 · 21% week · 2d6h');
    // Expired or malformed windows are not candidates at all.
    assert.equal(value({ five_hour: five(99, 5000), seven_day: week(21) }), 'Opus 5 · 21% week · 2d6h');
    assert.equal(value({ five_hour: five(-1) }), 'Opus 5');
    assert.equal(value({ five_hour: { used_percentage: '19', resets_at: 20000 } }), 'Opus 5');
});
test('Copilot auto mode reports the model it routed to, and forgets it on a pinned switch', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-auto-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'events.jsonl');
    const write = records => fs.writeFileSync(file, records.map(r => JSON.stringify(r)).join('\n') + '\n');
    const change = newModel => ({ type: 'session.model_change', data: { newModel } });
    const resolved = chosenModel => ({ type: 'session.auto_mode_resolved', data: { chosenModel } });
    // "auto" is the router's name; the pill must show what it chose.
    write([change('auto'), resolved('gpt-5.6-luna')]);
    let state = await sessionState('copilot', file);
    assert.equal(state.model, 'auto');
    assert.equal(modelName('copilot', state), 'gpt-5.6-luna');
    // Auto can route elsewhere on a later turn; the newest decision wins.
    write([change('auto'), resolved('gpt-5.6-luna'), resolved('claude-sonnet-5')]);
    assert.equal(modelName('copilot', await sessionState('copilot', file)), 'claude-sonnet-5');
    // Pinning a model must drop the resolution rather than keep naming it.
    write([change('auto'), resolved('gpt-5.6-luna'), change('claude-opus-5')]);
    state = await sessionState('copilot', file);
    assert.equal(state.autoModel, null);
    assert.equal(modelName('copilot', state), 'claude-opus-5');
    // Auto before its first routed turn has nothing better than the mode name.
    write([change('auto')]);
    assert.equal(modelName('copilot', await sessionState('copilot', file)), 'auto');
    // Codex never has a resolution and must be passed through untouched.
    assert.equal(modelName('codex', { model: 'auto', autoModel: 'gpt-5.6-luna' }), 'auto');
});
test('incremental reads resume at complete records and recover from rotation and truncation', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-tail-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-tail.jsonl');
    const record = model => JSON.stringify({ type: 'turn_context', payload: { model } }) + '\n';
    const first = record('first');
    fs.writeFileSync(file, first);
    assert.equal((await sessionState('codex', file)).model, 'first');
    const next = Buffer.from(record('second-🤖'));
    // Split in the middle of a multibyte character, as a concurrent writer can.
    fs.appendFileSync(file, next.subarray(0, next.length - 5));
    assert.equal((await sessionState('codex', file)).model, 'first');
    const original = fs.createReadStream;
    const starts = [];
    fs.createReadStream = (name, options) => { starts.push(options.start); return original(name, options); };
    try {
        fs.appendFileSync(file, next.subarray(next.length - 5));
        assert.equal((await sessionState('codex', file)).model, 'second-🤖');
        assert.deepEqual(starts, [Buffer.byteLength(first)]);
        await sessionState('codex', file);
        assert.equal(starts.length, 1, 'unchanged transcript should not be opened');
        fs.writeFileSync(file, record('x'));
        assert.equal((await sessionState('codex', file)).model, 'x');
        assert.equal(starts.at(-1), 0);
        fs.renameSync(file, file + '.old');
        fs.writeFileSync(file, record('replacement-longer-than-original'));
        assert.equal((await sessionState('codex', file)).model, 'replacement-longer-than-original');
        assert.equal(starts.at(-1), 0);
    } finally { fs.createReadStream = original; }
});
test('idle watcher skips process scans and all expensive data work', async () => {
    const calls = [];
    await refresh({
        run: (command, args) => { calls.push([command, args[0]]); return '1|2|fish\n1|3|nvim\n'; },
        processes: () => { throw new Error('idle process scan'); },
    });
    assert.deepEqual(calls, [['tmux', 'list-panes']]);
});
test('concurrent writers leave one complete cache value and no temporary files', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-write-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'cache.json');
    await Promise.all(Array.from({ length: 8 }, (_, i) => new Promise((resolve, reject) => {
        const child = spawn(process.execPath, ['--input-type=module', '-e', 'import(process.env.INITD_AGENT_HELPER).then(m => m.atomic(process.env.INITD_TARGET, JSON.stringify({writer:process.env.INITD_WRITER,value:"x".repeat(10000)})))'], {
            env: { ...process.env, INITD_AGENT_HELPER: helper, INITD_TARGET: file, INITD_WRITER: String(i) },
        });
        child.on('error', reject);
        child.on('exit', code => code === 0 ? resolve() : reject(new Error(`writer exited ${code}`)));
    })));
    assert.equal(JSON.parse(fs.readFileSync(file)).value.length, 10000);
    assert.deepEqual(fs.readdirSync(dir), ['cache.json']);
});
test('one asynchronous lsof scan covers all agents and does not delay Claude', async () => {
    const writes = [];
    const calls = [];
    let release;
    const lookup = new Promise(resolve => { release = resolve; });
    const pending = refresh({
        run(command, args) {
            calls.push([command, args]);
            return command === 'tmux' ? '1|10|codex\n1|20|copilot\n1|30|claude' : lookup;
        },
        processes: async () => [
            { pid: 10, parent: 1, agent: 'codex' },
            { pid: 20, parent: 1, agent: 'copilot' },
            { pid: 30, parent: 1, agent: 'claude' },
        ],
        atomic: (file, value) => writes.push([file, value]),
    });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(writes.length, 1);
    assert.match(writes[0][1], /\nclaude\n/);
    assert.deepEqual(calls.filter(c => c[0] === 'lsof'), [['lsof', ['-a', '-p', '10,20', '-Fn']]]);
    release(''); // timeout/unavailable lookup still emits safe icon-only caches
    await pending;
    assert.equal(writes.length, 3);
    const files = openFilesByPid('nignored\np10\nn/tmp/rollout-one.jsonl\np20\nn/tmp/session-state/two/events.jsonl\n');
    assert.equal(sessionFile('codex', files.get(10)), '/tmp/rollout-one.jsonl');
    assert.equal(sessionFile('copilot', files.get(20)), '/tmp/session-state/two/events.jsonl');
    assert.equal(files.size, 2);
});
test('publisher renders every pill and sends well-formed set-option commands', async () => {
    const sent = [];
    const runCommand = async (command, args) => {
        if (command === 'tmux' && args[0] === 'list-panes') return '%1\t100\t200\tclaude\t/repo\t1\n';
        if (command === 'tmux' && args[0] === 'list-windows') return '@1 \n';
        if (command === 'git' && args.includes('symbolic-ref')) return 'main\n';
        if (command === 'tmux') sent.push(args);
        return '';
    };
    const now = 1000;
    const publish = createStatusPublisher(runCommand, () => `${now}\nclaude\nOpus 5 · 12%\n`, async () => '87%');
    await publish(now);
    // Every option change goes in one invocation, as a ';'-separated sequence.
    assert.equal(sent.length, 1);
    const commands = sent[0].reduce((all, arg) => arg === ';' ? [...all, []]
        : [...all.slice(0, -1), [...all.at(-1), arg]], [[]]);
    assert.ok(commands.length > 1);
    // tmux rejects an option change that does not name the set-option command.
    for (const args of commands) assert.equal(args[0], 'set-option');
    const option = name => commands.find(args => args.includes(name))?.at(-1) ?? '';
    assert.match(option('@initd-battery'), /87%/);
    assert.match(option('@initd-agent-pill'), /Opus 5 · 12%/);
    assert.match(option('@initd-git-pill'), /main/);
    assert.deepEqual(commands.find(args => args.includes('@initd-agent'))?.slice(0, 4), ['set-option', '-p', '-t', '%1']);
    assert.match(option('@emoji'), /\p{Emoji}/u);
});
test('a pane path of exactly ";" is escaped so it cannot split the command sequence', async () => {
    let sent = [];
    const runCommand = async (command, args) => {
        if (command === 'tmux' && args[0] === 'list-panes') return '%1\t100\t200\tclaude\t;\t1\n';
        if (command === 'tmux' && args[0] === 'list-windows') return '@1 \n';
        if (command === 'tmux') sent = args;
        return '';
    };
    await createStatusPublisher(runCommand, () => '', async () => '')(1000);
    const directory = sent[sent.indexOf('@initd-directory') + 1];
    assert.equal(directory, '\\;', 'a bare ; would start a new tmux command');
    const commands = sent.reduce((all, arg) => arg === ';' ? [...all, []]
        : [...all.slice(0, -1), [...all.at(-1), arg]], [[]]);
    assert.equal(sent.filter(arg => arg === ';').length, commands.length - 1,
        'one separator between commands, none extra');
});
