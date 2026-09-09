import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { claudeValue } from './configs/tmux/.config/tmux/tmux.mjs';
import { queryQuota, createQuotaCache, quotaValue } from './configs/tmux/.config/tmux/copilot-quota.mjs';
const account = { host: 'https://github.com', login: 'work-user' };
const binding = { process: '42:start:1', account };
test('Claude prioritizes enterprise budgets, supports overage, and keeps subscription format', () => {
    const data = { model: { display_name: 'Sonnet' }, rate_limits: {
        spend_limit: { used_percentage: 125, resets_at: 90000 },
        five_hour: { used_percentage: 30, resets_at: 3600 },
    } };
    assert.equal(claudeValue(data, 0), 'Sonnet · 125% budget · 1d1h');
    delete data.rate_limits.spend_limit;
    assert.equal(claudeValue(data, 0), 'Sonnet · 30% · 1h0m');
    assert.equal(claudeValue(data, 3600), 'Sonnet');
    data.rate_limits.seven_day = { used_percentage: 50, resets_at: 90000 };
    assert.equal(claudeValue(data, 3600), 'Sonnet · 50% week · 1d0h');
});
test('Copilot distinguishes credits, requests, unlimited entitlements and absent quotas', () => {
    const q = { entitlementRequests: 100, remainingPercentage: 60, resetDate: new Date(86400000).toISOString() };
    assert.equal(quotaValue({ quotaSnapshots: { premium_interactions: q } }, 0), ' · 40% requests · 1d0h');
    assert.equal(quotaValue({ quotaSnapshots: { premium_interactions: { ...q, tokenBasedBilling: true } } }, 0), ' · 40% credits · 1d0h');
    assert.equal(quotaValue({ quotaSnapshots: { premium_interactions: { ...q, entitlementRequests: -1 } } }), ' · requests ∞');
    assert.equal(quotaValue({ quotaSnapshots: { premium_interactions: { ...q, hasQuota: false }, chat: q } }, 0), ' · 40% chat · 1d0h');
    assert.equal(quotaValue({ quotaSnapshots: { premium_interactions: { ...q, remainingPercentage: 100 } } }, 86400), ' · 0% requests');
    assert.equal(quotaValue({ quotaSnapshots: { premium_interactions: { ...q, entitlementRequests: 0 } } }), '');
    assert.equal(quotaValue(null), '');
});
// Stands in for the Copilot CLI over its stdio transport; only what the RPC touches.
function runtime(reply) {
    const child = new EventEmitter();
    child.stdin = new PassThrough(); child.stdout = new PassThrough();
    child.kill = () => { child.killed = true; queueMicrotask(() => child.emit('close')); };
    child.requests = [];
    child.stdin.on('data', bytes => {
        child.request = bytes.toString();
        const request = JSON.parse(child.request.split('\r\n\r\n')[1]);
        child.requests.push(request);
        reply(child, request);
    });
    return child;
}
const frame = message => {
    const body = JSON.stringify(message);
    return Buffer.from(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
};
test('quota RPC handles fragmented frames and notifications, then closes the runtime', async () => {
    const child = runtime((c, request) => queueMicrotask(() => {
        const result = request.method === 'account.getQuota' ? { quotaSnapshots: {} } : { authInfo: { ...account, token: 'never-return-this' } };
        const bytes = Buffer.concat([frame({ method: 'notification' }), frame({ id: request.id, result })]);
        c.stdout.write(bytes.subarray(0, 17)); c.stdout.write(bytes.subarray(17));
    }));
    assert.deepEqual(await queryQuota('/tmp', { launch: () => child, account }), { quotaSnapshots: {} });
    assert.deepEqual(child.requests.map(r => r.method), ['account.getCurrentAuth', 'account.getQuota', 'account.getCurrentAuth']);
    assert.equal(child.killed, true);
});
test('quota RPC times out and redacts server error details', async () => {
    const stalled = runtime(() => {});
    await assert.rejects(queryQuota('/tmp', { launch: () => stalled, timeout: 10, account }), /timed out/);
    assert.equal(stalled.killed, true);
    const failed = runtime(c => queueMicrotask(() => c.stdout.write(frame({ id: 1, error: { message: 'private auth detail' } }))));
    await assert.rejects(queryQuota('/tmp', { launch: () => failed, account }), error => !error.message.includes('private auth detail'));
});
test('quota cache is scoped by home and process/account, deduplicates and refreshes without flicker', async () => {
    const calls = [];
    const cache = createQuotaCache(async home => { calls.push(home); return { home }; });
    assert.equal(cache('/work', binding, 0), null);
    assert.equal(cache('/work', binding, 1), null);
    cache('/personal', binding, 1);
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(calls, ['/work', '/personal']);
    assert.deepEqual(cache('/work', binding, 119999), { home: '/work' });
    assert.deepEqual(cache('/work', binding, 120000), { home: '/work' });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls.length, 3);
    assert.equal(cache('/work', { ...binding, process: 'new-process' }, 120001), null);
    assert.equal(cache('/work', { ...binding, account: { ...account, login: 'personal-user' } }, 120001), null);
    assert.equal(cache('/work', null, 120001), null);
});
test('mismatched, unidentifiable and changing accounts never return quota', async () => {
    // A runtime that cannot name its own account is still refused.
    const nameless = runtime((c, r) => queueMicrotask(() => c.stdout.write(frame({ id: r.id, result: { authInfo: {} } }))));
    await assert.rejects(queryQuota('/tmp', { launch: () => nameless }), /do not match/);
    assert.equal(nameless.requests.length, 1, 'must not query quota without an identity');
    for (const mismatch of [{ ...account, login: 'personal-user' }, { ...account, host: 'https://work.ghe.com' }, {}]) {
        const child = runtime((c, r) => queueMicrotask(() => c.stdout.write(frame({ id: r.id, result: { authInfo: mismatch } }))));
        await assert.rejects(queryQuota('/tmp', { account, launch: () => child }), /do not match/);
        assert.equal(child.requests.length, 1, 'must not query quota for another account');
    }
    const child = runtime((c, r) => queueMicrotask(() => c.stdout.write(frame({ id: r.id, result:
        r.id === 1 ? { authInfo: account } : r.id === 2 ? { quotaSnapshots: {} } : { authInfo: { ...account, login: 'switched' } },
    }))));
    await assert.rejects(queryQuota('/tmp', { account, launch: () => child }), /do not match/);
});
test('a device-flow login takes its identity from the runtime and still detects a switch', async () => {
    // The pane log says "for account (device)", so no account reaches queryQuota.
    const answer = last => (c, r) => queueMicrotask(() => c.stdout.write(frame({ id: r.id, result:
        r.id === 2 ? { quotaSnapshots: { chat: { entitlementRequests: 200, remainingPercentage: 98.4 } } }
            : { authInfo: r.id === 3 ? last : account },
    })));
    const ok = runtime(answer(account));
    assert.deepEqual(await queryQuota('/tmp', { launch: () => ok }),
        { quotaSnapshots: { chat: { entitlementRequests: 200, remainingPercentage: 98.4 } } });
    assert.deepEqual(ok.requests.map(r => r.method),
        ['account.getCurrentAuth', 'account.getQuota', 'account.getCurrentAuth']);
    // Adopting an identity must not disable the after-the-fact switch check.
    const switched = runtime(answer({ ...account, login: 'someone-else' }));
    await assert.rejects(queryQuota('/tmp', { launch: () => switched }), /do not match/);
    // The cache keys a device-flow pane by its process, and still refuses no process.
    const seen = [];
    const cache = createQuotaCache(async home => { seen.push(home); return { quotaSnapshots: {} }; });
    assert.equal(cache('/home', { process: '42:start:undefined' }, 0), null);
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(cache('/home', { process: '42:start:undefined' }, 1), { quotaSnapshots: {} });
    assert.equal(cache('/home', {}, 1), null);
    assert.deepEqual(seen, ['/home']);
});
test('refresh failure clears quota and pending refresh has a hard staleness limit', async () => {
    let rejectRefresh;
    let calls = 0;
    const cache = createQuotaCache(() => ++calls === 1 ? Promise.resolve({ quotaSnapshots: {} })
        : new Promise((resolve, reject) => { rejectRefresh = reject; }));
    cache('/work', binding, 0);
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(cache('/work', binding, 120000), { quotaSnapshots: {} });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(cache('/work', binding, 135000), null);
    assert.equal(calls, 2);
    rejectRefresh(new Error('unavailable'));
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(cache('/work', binding, 135001), null);
});
test('refresh errors clear a still-fresh retained value immediately', async () => {
    let calls = 0;
    const cache = createQuotaCache(async () => {
        if (++calls > 1) throw new Error('authentication failed');
        return { quotaSnapshots: {} };
    });
    cache('/work', binding, 0);
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(cache('/work', binding, 120000), { quotaSnapshots: {} });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(cache('/work', binding, 120001), null);
});
test('cache pressure does not evict pending requests or cause duplicate launches', async () => {
    let calls = 0;
    const cache = createQuotaCache(() => { calls++; return new Promise(() => {}); });
    for (let pass = 0; pass < 2; pass++) {
        for (let i = 0; i < 40; i++) cache('/work', { ...binding, process: String(i) }, 0);
    }
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls, 32);
});
