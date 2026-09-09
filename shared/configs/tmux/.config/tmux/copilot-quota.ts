// Read-only Copilot SDK RPC over the installed CLI's stdio transport.
// No sessions/prompts, token extraction, SDK package, or telemetry export.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/** The GitHub host and login a Copilot pane is authenticated as. */
export interface CopilotAccount { host: string; login: string; }

export interface QuotaSnapshot {
    hasQuota?: boolean;
    tokenBasedBilling?: boolean;
    isUnlimitedEntitlement?: boolean;
    entitlementRequests?: number;
    remainingPercentage?: number;
    resetDate?: string;
}

export interface QuotaResult { quotaSnapshots?: Record<string, QuotaSnapshot | undefined>; }

/** Binds a cached quota to one process and login, so neither can be reused across a switch. */
export interface QuotaBinding { process: string; account?: Partial<CopilotAccount> | null; }

// Only the handful of members the RPC touches, so a test can supply a double
// without reproducing every overload of child_process.spawn.
export interface QuotaRuntime {
    stdin: { write(chunk: string): unknown; on(event: 'error', listener: () => void): unknown };
    stdout: { on(event: 'data', listener: (chunk: Buffer) => void): unknown };
    kill(signal?: NodeJS.Signals): unknown;
    on(event: 'error' | 'exit', listener: () => void): unknown;
    once(event: 'close', listener: () => void): unknown;
}
export type LaunchRuntime = (command: string, args: string[], options: object) => QuotaRuntime;

const filename = fileURLToPath(import.meta.url);
function accountKey(account: Partial<CopilotAccount> | null | undefined): string | null {
    if (typeof account?.host !== 'string' || typeof account?.login !== 'string') return null;
    try {
        const host = new URL(account.host);
        if (host.protocol !== 'https:' || host.username || host.password || host.search || host.hash
            || host.pathname !== '/' || !/^[a-z0-9][a-z0-9_-]*$/i.test(account.login)) return null;
        return `${host.origin}/${account.login.toLowerCase()}`;
    } catch { return null; }
}
function queryQuota(home: string, { launch = spawn as LaunchRuntime, timeout = 15000, account }: {
    launch?: LaunchRuntime; timeout?: number; account?: Partial<CopilotAccount> | null;
} = {}): Promise<QuotaResult | undefined> {
    const expected = accountKey(account);
    if (!expected) return Promise.reject(new Error('Pane account unavailable'));
    return new Promise<QuotaResult | undefined>((resolve, reject) => {
        const child = launch('copilot', ['--headless', '--stdio', '--no-auto-update', '--log-level', 'none'], {
            env: { ...process.env, COPILOT_HOME: home, COPILOT_OTEL_ENABLED: 'false' },
            cwd: home, stdio: ['pipe', 'pipe', 'ignore'],
        });
        let buffer = Buffer.alloc(0);
        let done = false;
        let requestId = 1;
        let quota: QuotaResult | undefined;
        function request(method: string): void {
            const body = JSON.stringify({ jsonrpc: '2.0', id: requestId, method, params: {} });
            child.stdin.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
        }
        const timer = setTimeout(() => finish(new Error('Quota request timed out')), timeout);
        function finish(error: Error | null, result?: QuotaResult): void {
            if (done) return;
            done = true;
            clearTimeout(timer);
            child.kill('SIGTERM');
            const reap = setTimeout(() => child.kill('SIGKILL'), 1000);
            reap.unref();
            child.once('close', () => clearTimeout(reap));
            if (error) reject(error); else resolve(result);
        }
        child.on('error', () => finish(new Error('Copilot unavailable')));
        child.on('exit', () => finish(new Error('Copilot exited before quota response')));
        child.stdin.on('error', () => finish(new Error('Copilot connection closed')));
        child.stdout.on('data', chunk => {
            buffer = Buffer.concat([buffer, chunk]);
            if (buffer.length > 1024 * 1024) return finish(new Error('Quota response too large'));
            while (!done) {
                const boundary = buffer.indexOf('\r\n\r\n');
                if (boundary < 0) return;
                const match = buffer.subarray(0, boundary).toString().match(/(?:^|\r\n)Content-Length: (\d+)/i);
                const size = Number(match?.[1]);
                if (!Number.isSafeInteger(size) || size < 0 || size > 1024 * 1024) return finish(new Error('Invalid quota frame'));
                if (buffer.length < boundary + 4 + size) return;
                const payload = buffer.subarray(boundary + 4, boundary + 4 + size);
                buffer = buffer.subarray(boundary + 4 + size);
                try {
                    const message = JSON.parse(payload.toString());
                    if (message.id !== requestId) continue;
                    // Do not log runtime error text: it can contain account details.
                    if (message.error) return finish(new Error('Quota unavailable for this login/runtime'));
                    if (requestId === 2) {
                        quota = message.result;
                    } else if (accountKey(message.result?.authInfo) !== expected) {
                        return finish(new Error('Pane and quota accounts do not match'));
                    }
                    if (requestId === 3) return finish(null, quota);
                    requestId++;
                    request(requestId === 2 ? 'account.getQuota' : 'account.getCurrentAuth');
                } catch { finish(new Error('Invalid quota JSON')); }
            }
        });
        // Check the host/login both before and after the quota read. Never
        // return authInfo (some runtimes include credentials in that object).
        request('account.getCurrentAuth');
    });
}
// One request per process/account binding every two minutes, only when requested by
// a live pane. Failures clear the old value; no account data is saved to disk.
interface QuotaEntry { at: number; pending: boolean; value: QuotaResult | null; goodAt: number; }
function createQuotaCache(query = queryQuota) {
    const entries = new Map<string, QuotaEntry>();
    return (home: string, binding: QuotaBinding | null | undefined, now = Date.now()): QuotaResult | null => {
        const identity = accountKey(binding?.account);
        if (!identity || !binding?.process) return null;
        const key = JSON.stringify([home, binding.process, identity]);
        const account = { ...binding.account };
        let entry = entries.get(key);
        if (!entry || (!entry.pending && now - entry.at >= 120000)) {
            // Never evict pending or fresh entries: that would duplicate work
            // when many panes repeatedly request the same bindings.
            if (!entry && entries.size >= 32) {
                for (const [oldKey, old] of entries) {
                    if (!old.pending && now - old.at >= 135000) entries.delete(oldKey);
                }
                if (entries.size >= 32) return null;
            }
            const started: QuotaEntry = { at: now, pending: true, value: entry?.value ?? null, goodAt: entry?.goodAt ?? now };
            entry = started;
            entries.set(key, started);
            Promise.resolve().then(() => query(home, { account })).then(value => { started.value = value ?? null; started.goodAt = now; })
                .catch(() => { started.value = null; }).finally(() => { started.pending = false; });
        }
        // Retain a matching successful snapshot through the 15s refresh, but
        // never indefinitely if a request stalls. Failures clear it immediately.
        return now - entry.goodAt < 135000 ? entry.value : null;
    };
}
function quotaValue(data: QuotaResult | null | undefined, now = Date.now() / 1000): string {
    const snapshots = data?.quotaSnapshots;
    for (const key of ['premium_interactions', 'chat']) {
        const quota = snapshots?.[key];
        if (!quota || quota.hasQuota === false) continue;
        const label = quota.tokenBasedBilling ? 'credits' : key === 'chat' ? 'chat' : 'requests';
        if (quota.isUnlimitedEntitlement || quota.entitlementRequests === -1) return ` · ${label} ∞`;
        const entitlement = quota.entitlementRequests;
        const remaining = quota.remainingPercentage;
        if (!(entitlement !== undefined && entitlement > 0) || !Number.isFinite(remaining)) continue;
        if (remaining === undefined || remaining < 0 || remaining > 100) continue;
        let value = ` · ${Math.round(100 - remaining)}% ${label}`;
        const reset = Date.parse(quota.resetDate ?? '') / 1000;
        // Some runtimes substitute the fetch time when no reset date is known.
        if (reset > now) {
            const mins = Math.ceil((reset - now) / 60);
            value += mins >= 1440 ? ` · ${Math.floor(mins / 1440)}d${Math.floor(mins % 1440 / 60)}h`
                : ` · ${Math.floor(mins / 60)}h${mins % 60}m`;
        }
        return value;
    }
    return '';
}
export { queryQuota, createQuotaCache, quotaValue, accountKey };
let invokedDirectly = false;
try { invokedDirectly = Boolean(process.argv[1]) && fs.realpathSync(process.argv[1]!) === filename; } catch {}
if (invokedDirectly) queryQuota(process.argv[2] || path.join(process.env.HOME ?? '', '.copilot'),
    { account: { host: process.argv[3] ?? '', login: process.argv[4] ?? '' } })
    .then(result => console.log(quotaValue(result))).catch((error: Error) => { console.error(error.message); process.exitCode = 1; });
