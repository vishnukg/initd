import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { findAgent, sessionFile, copilotSessionFile, sessionState, claudeValue, codexUsage, refresh, openFilesByPid, createStatusPublisher } from './configs/tmux/.config/tmux/tmux.mjs';
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
test('Claude can show its model without rate limits and strips tmux formatting', () => {
    assert.equal(claudeValue({ model: { display_name: 'Sonnet' } }), 'Sonnet');
    assert.equal(claudeValue({ model: { display_name: '#[bg=red]\nSonnet' } }), '[bg=red]Sonnet');
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
