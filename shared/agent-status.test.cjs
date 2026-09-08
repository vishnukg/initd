const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const helper = path.join(__dirname, 'configs/tmux/.config/tmux/agent-status.cjs');
const { findAgent, sessionFile, copilotSessionFile, sessionState, claudeValue, codexUsage, refresh } = require(helper);

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
    ].map(JSON.stringify).join('\n') + '\n{"partial":');
    assert.deepEqual(await sessionState('codex', file), { id: 'rollout-a', model: 'new-model' });
    fs.writeFileSync(file, [
        { type: 'session.model_change', data: { newModel: 'chosen-model' } },
        { type: 'model.turn_started', data: { model: 'auxiliary-model' } },
        { type: 'session.model_change', data: { newModel: 'auto' } },
    ].map(JSON.stringify).join('\n') + '\n');
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
    ].map(JSON.stringify).join('\n') + '\n{"partial":');
    assert.deepEqual((await sessionState('codex', file)).rateLimits, latest);
    assert.equal((await sessionState('codex', file)).rateLimits.primary.used_percent, 31);
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
        const child = spawn(process.execPath, ['-e', 'require(process.argv[1]).atomic(process.argv[2], JSON.stringify({writer:process.argv[3],value:"x".repeat(10000)}))', helper, file, String(i)]);
        child.on('error', reject);
        child.on('exit', code => code === 0 ? resolve() : reject(new Error(`writer exited ${code}`)));
    })));
    assert.equal(JSON.parse(fs.readFileSync(file)).value.length, 10000);
    assert.deepEqual(fs.readdirSync(dir), ['cache.json']);
});
