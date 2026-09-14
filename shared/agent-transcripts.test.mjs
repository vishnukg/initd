import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { sessionState, modelName } from './configs/tmux/.config/tmux/tmux.mjs';
import { codexUsage, codexLimit } from './configs/tmux/.config/tmux/status-renderer.mjs';

test('model switches use the latest context, not historical usage or auxiliary calls', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-test-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-a.jsonl');
    fs.writeFileSync(file, [
        { type: 'turn_context', payload: { model: 'old-model' } },
        { type: 'turn_context', payload: { model: 'new-model' } },
        { type: 'event_msg', payload: { model: 'old-model' } },
    ].map(record => JSON.stringify(record)).join('\n') + '\n{"partial":');

    // Act
    const sessionStateResult = await sessionState('codex', file);

    // Assert
    assert.deepEqual(sessionStateResult, { id: 'rollout-a', model: 'new-model' });

    // Arrange
    fs.writeFileSync(file, [
        { type: 'session.model_change', data: { newModel: 'chosen-model' } },
        { type: 'model.turn_started', data: { model: 'auxiliary-model' } },
        { type: 'session.model_change', data: { newModel: 'auto' } },
    ].map(record => JSON.stringify(record)).join('\n') + '\n');

    // Act
    const sessionStateResult2 = (await sessionState('copilot', file)).model;

    // Assert
    assert.equal(sessionStateResult2, 'auto');
});

test('Codex reads the latest account quota snapshot, ignoring unrelated limits and partial writes', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-quota-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-quota.jsonl');
    const latest = { limit_id: 'codex', primary: { used_percent: 31, window_minutes: 300, resets_at: 20000 } };
    const event = rate_limits => ({ type: 'event_msg', payload: { type: 'token_count', rate_limits } });
    fs.writeFileSync(file, [event({ ...latest, primary: { used_percent: 20 } }), event(latest),
        event({ limit_id: 'other-model', primary: { used_percent: 99 } }), event(null),
    ].map(record => JSON.stringify(record)).join('\n') + '\n{"partial":');

    // Act
    const sessionStateResult = (await sessionState('codex', file)).rateLimits;
    const sessionStateResult2 = (await sessionState('codex', file)).rateLimits.primary.used_percent;

    // Assert
    assert.deepEqual(sessionStateResult, latest);
    assert.equal(sessionStateResult2, 31);
});

test('Codex account limits are taken under either id, and a per-model one is ignored', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-limitid-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-limit.jsonl');
    const event = rate_limits => JSON.stringify({ type: 'event_msg', payload: { type: 'token_count', rate_limits } });
    const premium = { limit_id: 'premium', primary: { used_percent: 42, resets_at: 20000 } };
    // Codex renamed the account limit to "premium"; a per-model id must not win.
    fs.writeFileSync(file, [event({ limit_id: 'codex', primary: { used_percent: 7 } }), event(premium),
        event({ limit_id: 'other-model', primary: { used_percent: 99 } })].join('\n') + '\n');

    // Act
    const sessionStateResult = (await sessionState('codex', file)).rateLimits;
    const codexUsageResult = codexUsage(premium, 5600);

    // Assert
    assert.deepEqual(sessionStateResult, premium);
    assert.equal(codexUsageResult, ' · 42% · 4h0m');

    // Arrange
    // The payload Codex actually sends today carries no usage at all.
    const empty = { limit_id: 'premium', primary: null, secondary: null, credits: { has_credits: false, balance: '0' } };

    // Act
    const codexUsageResult2 = codexUsage(empty);

    // Assert
    assert.equal(codexUsageResult2, '');
});

test('Codex percentage includes zero, ticks down on cached data, and hides expired or invalid quota', () => {
    // Arrange
    const limits = { primary: { used_percent: 31, resets_at: 20000 } };

    // Act
    const codexUsageResult = codexUsage(limits, 5600);
    const codexUsageResult2 = codexUsage(limits, 5660);
    const codexUsageResult3 = codexUsage(limits, 20000);
    const codexUsageResult4 = codexUsage({ primary: { used_percent: 0 } }, 0);
    const codexUsageResult5 = codexUsage(null);
    const codexUsageResult6 = codexUsage({ primary: { used_percent: '31' } });
    const codexUsageResult7 = codexUsage({ primary: { used_percent: -1 } });

    // Assert
    assert.equal(codexUsageResult, ' · 31% · 4h0m');
    assert.equal(codexUsageResult2, ' · 31% · 3h59m');
    assert.equal(codexUsageResult3, '');
    assert.equal(codexUsageResult4, ' · 0%');
    assert.equal(codexUsageResult5, '');
    assert.equal(codexUsageResult6, '');
    assert.equal(codexUsageResult7, '');
});

test('a model switched between turns is reported at once, not one turn late', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-switch-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-switch.jsonl');
    const turn = model => JSON.stringify({ type: 'turn_context', payload: { model } });
    const applied = model => JSON.stringify({
        type: 'event_msg', payload: { type: 'thread_settings_applied', thread_settings: { model } },
    });
    // A switch after the last turn wins; the next turn then confirms it.
    fs.writeFileSync(file, [turn('gpt-old'), applied('gpt-new')].join('\n') + '\n');

    // Act
    const sessionStateResult = (await sessionState('codex', file)).model;

    // Assert
    assert.equal(sessionStateResult, 'gpt-new');

    // Arrange
    fs.appendFileSync(file, turn('gpt-new') + '\n');

    // Act
    const sessionStateResult2 = (await sessionState('codex', file)).model;

    // Assert
    assert.equal(sessionStateResult2, 'gpt-new');

    // Arrange
    // Settings carrying no model must not blank a model already known.
    fs.appendFileSync(file, JSON.stringify({
        type: 'event_msg', payload: { type: 'thread_settings_applied', thread_settings: {} },
    }) + '\n');

    // Act
    const sessionStateResult3 = (await sessionState('codex', file)).model;

    // Assert
    assert.equal(sessionStateResult3, 'gpt-new');
});

test('an exhausted Codex account says so, and any later turn clears it', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-exhausted-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-exhausted.jsonl');
    const complete = error => JSON.stringify({ type: 'event_msg', payload: { type: 'task_complete', error } });
    const message = "You've hit your usage limit. Upgrade to Plus to continue using Codex "
        + '(https://chatgpt.com/explore/plus), or try again at Sep 13th, 2026 6:05 PM.';
    fs.writeFileSync(file, complete({ message, codex_error_info: 'usage_limit_exceeded' }) + '\n');

    // Act
    const sessionStateResult = (await sessionState('codex', file)).limit;

    // Assert
    assert.equal(sessionStateResult, message);

    // Arrange
    const reset = Date.parse('Sep 13, 2026 6:05 PM') / 1000;

    // Act
    const codexLimitResult = codexLimit(message, reset - 3 * 86400 - 16 * 3600);
    const codexLimitResult2 = codexLimit(message, reset - 90 * 60);

    // Assert
    assert.equal(codexLimitResult, ' · limit · 3d16h');
    assert.equal(codexLimitResult2, ' · limit · 1h30m');

    // Act
    // Once the reset has passed the countdown is gone, but the turn still failed.
    const codexLimitResult3 = codexLimit(message, reset);

    // Assert
    assert.equal(codexLimitResult3, ' · limit');

    // Act
    const codexLimitResult4 = codexLimit('out of quota, no date here');
    const codexLimitResult5 = codexLimit(null);

    // Assert
    assert.equal(codexLimitResult4, ' · limit');
    assert.equal(codexLimitResult5, '');

    // Arrange
    // A turn that runs at all clears the notice without waiting for the reset.
    fs.appendFileSync(file, complete(null) + '\n');

    // Act
    const sessionStateResult2 = (await sessionState('codex', file)).limit;

    // Assert
    assert.equal(sessionStateResult2, null);
});

test('Copilot auto mode reports the model it routed to, and forgets it on a pinned switch', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-auto-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'events.jsonl');
    const write = records => fs.writeFileSync(file, records.map(r => JSON.stringify(r)).join('\n') + '\n');
    const change = newModel => ({ type: 'session.model_change', data: { newModel } });
    const resolved = chosenModel => ({ type: 'session.auto_mode_resolved', data: { chosenModel } });
    // "auto" is the router's name; the pill must show what it chose.
    write([change('auto'), resolved('gpt-5.6-luna')]);

    // Act
    let state = await sessionState('copilot', file);

    // Assert
    assert.equal(state.model, 'auto');

    // Act
    const modelNameResult = modelName('copilot', state);

    // Assert
    assert.equal(modelNameResult, 'gpt-5.6-luna');

    // Arrange
    // Auto can route elsewhere on a later turn; the newest decision wins.
    write([change('auto'), resolved('gpt-5.6-luna'), resolved('claude-sonnet-5')]);

    // Act
    const modelNameResult2 = modelName('copilot', await sessionState('copilot', file));

    // Assert
    assert.equal(modelNameResult2, 'claude-sonnet-5');

    // Arrange
    // Pinning a model must drop the resolution rather than keep naming it.
    write([change('auto'), resolved('gpt-5.6-luna'), change('claude-opus-5')]);

    // Act
    state = await sessionState('copilot', file);

    // Assert
    assert.equal(state.autoModel, null);

    // Act
    const modelNameResult3 = modelName('copilot', state);

    // Assert
    assert.equal(modelNameResult3, 'claude-opus-5');

    // Arrange
    // Auto before its first routed turn has nothing better than the mode name.
    write([change('auto')]);

    // Act
    const modelNameResult4 = modelName('copilot', await sessionState('copilot', file));

    // Assert
    assert.equal(modelNameResult4, 'auto');

    // Act
    // Codex never has a resolution and must be passed through untouched.
    const modelNameResult5 = modelName('codex', { model: 'auto', autoModel: 'gpt-5.6-luna' });

    // Assert
    assert.equal(modelNameResult5, 'auto');
});

test('large transcript records are assembled with linear copying and preserve incomplete tails', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-large-record-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-large.jsonl');
    const record = JSON.stringify({ type: 'turn_context', payload: { padding: '🧬'.repeat(262144), model: 'large-model' } });
    fs.writeFileSync(file, record + '\n{"type":"turn_context","payload":{"model":"next');
    const concat = Buffer.concat;
    let copied = 0;
    t.mock.method(Buffer, 'concat', function (parts, length) {
        copied += length ?? parts.reduce((sum, part) => sum + part.length, 0);
        return concat(parts, length);
    });

    // Act
    const sessionStateResult = (await sessionState('codex', file)).model;

    // Assert
    assert.equal(sessionStateResult, 'large-model');
    assert.ok(copied <= fs.statSync(file).size * 2, 'copy volume must stay linear in record size');

    // Arrange
    fs.appendFileSync(file, '-model"}}\n');

    // Act
    const sessionStateResult2 = (await sessionState('codex', file)).model;

    // Assert
    assert.equal(sessionStateResult2, 'next-model');
});

test('a record streamed across many polls reads each byte only once', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-stream-record-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout.jsonl');
    const record = Buffer.from(JSON.stringify({
        type: 'turn_context', payload: { padding: 'x'.repeat(64 * 1024), model: 'streamed' },
    }) + '\n');
    fs.writeFileSync(file, '');
    const original = fs.createReadStream;
    let bytes = 0;
    const models = [];
    t.mock.method(fs, 'createReadStream', (name, options) => {
        const stream = original(name, options);
        stream.on('data', chunk => { bytes += chunk.length; });
        return stream;
    });

    // Act: append and poll as an agent streams one record in small writes.
    for (let start = 0; start < record.length; start += 4096) {
        fs.appendFileSync(file, record.subarray(start, start + 4096));
        models.push((await sessionState('codex', file)).model);
    }

    // Assert
    assert.ok(models.slice(0, -1).every(model => model === null), 'incomplete records must not update the model');
    assert.equal(models.at(-1), 'streamed');
    assert.equal(bytes, record.length, 'polling must not reread the incomplete record');
});

test('oversized unfinished records fall back to rereading and still resolve when complete', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-stream-oversized-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout.jsonl');
    const record = JSON.stringify({ type: 'turn_context', payload: {
        padding: 'x'.repeat(128 * 1024), model: 'large-model',
    } });
    fs.writeFileSync(file, record);
    const starts = [];
    const original = fs.createReadStream;
    t.mock.method(fs, 'createReadStream', (name, options) => {
        starts.push(options.start);
        return original(name, options);
    });

    // Act
    const incomplete = await sessionState('codex', file);
    fs.appendFileSync(file, '\n');
    const completed = await sessionState('codex', file);

    // Assert
    assert.equal(incomplete.model, null);
    assert.equal(completed.model, 'large-model');
    assert.deepEqual(starts, [0, 0], 'oversized tails use the original reread path instead of being retained');
});

test('incremental reads retain partial UTF-8 records and recover from rotation and truncation', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-tail-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'rollout-tail.jsonl');
    const record = model => JSON.stringify({ type: 'turn_context', payload: { model } }) + '\n';
    const first = record('first');
    const next = Buffer.from(record('second-🤖'));
    fs.writeFileSync(file, first);
    const starts = [];
    const original = fs.createReadStream;
    t.mock.method(fs, 'createReadStream', (name, options) => {
        starts.push(options.start);
        return original(name, options);
    });

    // Act: finish a split UTF-8 record, then truncate and replace the log.
    const initial = await sessionState('codex', file);
    fs.appendFileSync(file, next.subarray(0, next.length - 5));
    const incomplete = await sessionState('codex', file);
    fs.appendFileSync(file, next.subarray(next.length - 5));
    const completed = await sessionState('codex', file);
    const completedStarts = [...starts];
    await sessionState('codex', file);
    const readsAfterUnchangedPoll = starts.length;
    fs.writeFileSync(file, record('x'));
    const truncated = await sessionState('codex', file);
    const truncationStart = starts.at(-1);
    fs.renameSync(file, file + '.old');
    fs.writeFileSync(file, record('replacement-longer-than-original'));
    const rotated = await sessionState('codex', file);

    // Assert
    assert.equal(initial.model, 'first');
    assert.equal(incomplete.model, 'first');
    assert.equal(completed.model, 'second-🤖');
    assert.deepEqual(completedStarts, [0, Buffer.byteLength(first), Buffer.byteLength(first) + next.length - 5]);
    assert.equal(readsAfterUnchangedPoll, completedStarts.length, 'unchanged transcript should not be opened');
    assert.equal(truncated.model, 'x');
    assert.equal(truncationStart, 0);
    assert.equal(rotated.model, 'replacement-longer-than-original');
    assert.equal(starts.at(-1), 0);
});
