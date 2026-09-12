import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { sessionState } from './configs/tmux/.config/tmux/tmux.mjs';
import { claudeValue, copilotUsage } from './configs/tmux/.config/tmux/status-renderer.mjs';

test('Claude prioritizes enterprise budgets, supports overage, and keeps subscription format', () => {
    const data = { model: { display_name: 'Sonnet' }, rate_limits: {
        spend_limit: { used_percentage: 125, resets_at: 90000 },
        five_hour: { used_percentage: 30, resets_at: 3600 },
    } };
    assert.equal(claudeValue(data, 0), 'Sonnet · 125% budget · 1d1h');
    delete data.rate_limits.spend_limit;
    assert.equal(claudeValue(data, 0), 'Sonnet · 30% · 1h0m');
    assert.equal(claudeValue(data, 3600), 'Sonnet');
    // Exactly on ESCALATE_AT_PERCENT, which is inclusive: raise that constant and
    // this is the assertion that says so rather than failing somewhere vaguer.
    data.rate_limits.seven_day = { used_percentage: 50, resets_at: 90000 };
    assert.equal(claudeValue(data, 3600), 'Sonnet · 50% week · 1d0h');
});
test('Copilot distinguishes credits, requests, unlimited entitlements and absent quotas', () => {
    const q = { entitlementRequests: 100, remainingPercentage: 60, resetDate: new Date(86400000).toISOString() };
    assert.equal(copilotUsage({ quotaSnapshots: { premium_interactions: q } }, 0), ' · 40% requests · 1d0h');
    assert.equal(copilotUsage({ quotaSnapshots: { premium_interactions: { ...q, tokenBasedBilling: true } } }, 0), ' · 40% credits · 1d0h');
    assert.equal(copilotUsage({ quotaSnapshots: { premium_interactions: { ...q, entitlementRequests: -1 } } }), ' · requests ∞');
    assert.equal(copilotUsage({ quotaSnapshots: { premium_interactions: { ...q, hasQuota: false }, chat: q } }, 0), ' · 40% chat · 1d0h');
    assert.equal(copilotUsage({ quotaSnapshots: { premium_interactions: { ...q, remainingPercentage: 100 } } }, 86400), ' · 0% requests');
    assert.equal(copilotUsage({ quotaSnapshots: { premium_interactions: { ...q, entitlementRequests: 0 } } }), '');
    assert.equal(copilotUsage(null), '');
});
test('Copilot quota is read from the session transcript, latest call winning', async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-copilot-quota-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'events.jsonl');
    const snapshot = used => ({ quotaSnapshots: { chat: {
        entitlementRequests: 200, remainingPercentage: 100 - used, resetDate: new Date(86400000).toISOString(),
    } } });
    // The shape Copilot actually writes: quota rides on model.model_call_success.
    fs.writeFileSync(file, [
        { type: 'session.model_change', data: { newModel: 'auto' } },
        { type: 'model.model_call_success', data: snapshot(1) },
        { type: 'model.model_call_success', data: snapshot(2) },
        // Neither an unrelated event nor a call without quota may clear it.
        { type: 'model.turn_started', data: { model: 'other' } },
        { type: 'model.model_call_success', data: { latencyMs: 12 } },
    ].map(record => JSON.stringify(record)).join('\n') + '\n');
    const state = await sessionState('copilot', file);
    assert.equal(state.model, 'auto');
    assert.deepEqual(state.quota, snapshot(2));
    assert.equal(copilotUsage(state.quota, 0), ' · 2% chat · 1d0h');
    // A session that has not called a model yet simply has no quota to show.
    const fresh = path.join(dir, 'fresh.jsonl');
    fs.writeFileSync(fresh, JSON.stringify({ type: 'session.model_change', data: { newModel: 'auto' } }) + '\n');
    assert.equal((await sessionState('copilot', fresh)).quota, undefined);
    assert.equal(copilotUsage(undefined), '');
});
