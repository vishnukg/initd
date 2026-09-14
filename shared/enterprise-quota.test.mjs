import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { sessionState } from './configs/tmux/.config/tmux/tmux.mjs';
import { claudeValue, copilotUsage } from './configs/tmux/.config/tmux/status-renderer.mjs';

for (const { name, rateLimits, now, expected } of [
    { name: 'enterprise budget includes overage', now: 0, expected: 'Sonnet · 125% budget · 1d1h', rateLimits: {
        spend_limit: { used_percentage: 125, resets_at: 90000 },
        five_hour: { used_percentage: 30, resets_at: 3600 },
    } },
    { name: 'subscription keeps its existing format', now: 0, expected: 'Sonnet · 30% · 1h0m', rateLimits: {
        five_hour: { used_percentage: 30, resets_at: 3600 },
    } },
    { name: 'expired quota leaves only the model', now: 3600, expected: 'Sonnet', rateLimits: {
        five_hour: { used_percentage: 30, resets_at: 3600 },
    } },
    { name: 'weekly escalation includes the 50 percent boundary', now: 3600, expected: 'Sonnet · 50% week · 1d0h', rateLimits: {
        five_hour: { used_percentage: 30, resets_at: 3600 },
        seven_day: { used_percentage: 50, resets_at: 90000 },
    } },
]) {
    test(`Claude quota: ${name}`, () => {
        // Arrange
        const data = { model: { display_name: 'Sonnet' }, rate_limits: rateLimits };

        // Act
        const rendered = claudeValue(data, now);

        // Assert
        assert.equal(rendered, expected);
    });
}

for (const { name, premium = {}, chat = false, now = 0, expected, absent = false } of [
    { name: 'request entitlement', expected: ' · 40% requests · 1d0h' },
    { name: 'token billing', premium: { tokenBasedBilling: true }, expected: ' · 40% credits · 1d0h' },
    { name: 'unlimited entitlement', premium: { entitlementRequests: -1 }, expected: ' · requests ∞' },
    { name: 'chat fallback', premium: { hasQuota: false }, chat: true, expected: ' · 40% chat · 1d0h' },
    { name: 'unused quota after reset', premium: { remainingPercentage: 100 }, now: 86400, expected: ' · 0% requests' },
    { name: 'zero entitlement', premium: { entitlementRequests: 0 }, expected: '' },
    { name: 'absent quota', absent: true, expected: '' },
]) {
    test(`Copilot quota: ${name}`, () => {
        // Arrange
        const quota = { entitlementRequests: 100, remainingPercentage: 60, resetDate: new Date(86400000).toISOString() };
        const data = absent ? null : { quotaSnapshots: {
            premium_interactions: { ...quota, ...premium }, ...(chat ? { chat: quota } : {}),
        } };

        // Act
        const rendered = copilotUsage(data, now);

        // Assert
        assert.equal(rendered, expected);
    });
}

test('Copilot quota is read from the session transcript, latest call winning', async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-copilot-quota-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'events.jsonl');
    const snapshot = used => ({ quotaSnapshots: { chat: {
        entitlementRequests: 200, remainingPercentage: 100 - used, resetDate: new Date(86400000).toISOString(),
    } } });
    fs.writeFileSync(file, [
        { type: 'session.model_change', data: { newModel: 'auto' } },
        { type: 'model.model_call_success', data: snapshot(1) },
        { type: 'model.model_call_success', data: snapshot(2) },
        // Unrelated events and calls without quota must not erase the snapshot.
        { type: 'model.turn_started', data: { model: 'other' } },
        { type: 'model.model_call_success', data: { latencyMs: 12 } },
    ].map(record => JSON.stringify(record)).join('\n') + '\n');
    const fresh = path.join(dir, 'fresh.jsonl');
    fs.writeFileSync(fresh, JSON.stringify({ type: 'session.model_change', data: { newModel: 'auto' } }) + '\n');

    // Act
    const state = await sessionState('copilot', file);
    const rendered = copilotUsage(state.quota, 0);
    const freshState = await sessionState('copilot', fresh);
    const freshRendered = copilotUsage(freshState.quota);

    // Assert
    assert.equal(state.model, 'auto');
    assert.deepEqual(state.quota, snapshot(2));
    assert.equal(rendered, ' · 2% chat · 1d0h');
    assert.equal(freshState.quota, undefined);
    assert.equal(freshRendered, '');
});
