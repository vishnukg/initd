// Bind status to the pane's process and its open transcript, never log recency.
import fs from 'node:fs';
import path from 'node:path';
import { execFile, execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createQuotaCache, quotaValue, accountKey } from './copilot-quota.ts';
import type { CopilotAccount } from './copilot-quota.ts';
import { agentPill, battery, clean, gitPill, pill, readAgentCache } from './status-renderer.ts';
import type { RunCommand } from './status-renderer.ts';

/** One row of `ps -axo pid=,ppid=,lstart=,comm=`. */
export interface Proc { pid: number; parent: number; start: string; agent: string; }

interface CodexRateLimit { used_percent?: number; resets_at?: number; }
export interface CodexRateLimits { primary?: CodexRateLimit; limit_id?: string; }

/** Accumulated while replaying an agent's append-only transcript. */
export interface AgentState {
    model: string | null;
    id: string;
    rateLimits?: CodexRateLimits;
    sessionId?: string | null;
    account?: CopilotAccount | null;
    accountEpoch?: number;
}

interface ClaudeRateLimit { used_percentage?: number; resets_at?: number; }
/** The payload Claude Code pipes into the statusLine hook on stdin. */
export interface ClaudeHookData {
    model?: { id?: string; display_name?: string };
    rate_limits?: Record<string, ClaudeRateLimit | undefined>;
    context_window?: { used_percentage?: number };
}

interface TranscriptEntry {
    version: string; state: AgentState; ino: number; size: number; offset: number; bytesRead: number;
}

const filename = fileURLToPath(import.meta.url);
const copilotQuota = createQuotaCache();
const cacheDir = path.join(process.env.HOME ?? '', '.cache/initd-tmux');
const STATUS_REFRESH_MS = 1000;
const transcriptCache = new Map<string, TranscriptEntry>();
const sourceVersion = () => [filename, fileURLToPath(new URL('./copilot-quota.ts', import.meta.url))]
    .map(file => fs.statSync(file).mtimeMs).join(':');
const loadedVersion = sourceVersion();
function run(command: string, args: string[]): string {
    // ps lstart follows locale (e.g. "Sep 8" vs "8 Sep"); fix its wire format.
    try { return execFileSync(command, args, { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' }, timeout: 3000, maxBuffer: 8 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] }); }
    catch { return ''; }
}
const runAsync: RunCommand = (command, args) => {
    // lsof may return 1 when one requested process has just exited, while
    // still returning complete records for the other processes.
    return new Promise(resolve => execFile(command, args, {
        encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' },
        timeout: 3000, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024,
    }, (error, stdout) => resolve(error && !(command === 'lsof' && error.code === 1) ? '' : stdout)));
};
function openFilesByPid(output: string): Map<number, string> {
    const files = new Map<number, string>();
    let pid: number | undefined;
    for (const line of output.split('\n')) {
        if (/^p\d+$/.test(line)) { pid = Number(line.slice(1)); files.set(pid, ''); }
        else if (pid && line.startsWith('n')) files.set(pid, files.get(pid) + line + '\n');
    }
    return files;
}
function readJSON(file: string): unknown {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}
function atomic(file: string, value: string): void {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.${process.pid}.${randomUUID()}.tmp`;
    try { fs.writeFileSync(tmp, value, { mode: 0o600 }); fs.renameSync(tmp, file); }
    finally { try { fs.unlinkSync(tmp); } catch {} }
}
function processes(output = run('ps', ['-axo', 'pid=,ppid=,lstart=,comm='])): Proc[] {
    return output.trim().split('\n').flatMap(line => {
        const m = line.trim().match(/^(\d+)\s+(\d+)\s+(\S+\s+\S+\s+\d+\s+\S+\s+\d+)\s+(.+)$/);
        return m ? [{ pid: Number(m[1]), parent: Number(m[2]), start: m[3]!, agent: path.basename(m[4]!) }] : [];
    });
}
// Generic over the row shape: only pid/parent/agent are read, so callers (and
// tests) may pass anything carrying those without inventing a start time.
function findAgent<T extends { pid: number; parent: number; agent: string }>(
    procs: T[], root: number | string, agent: string,
): T | null {
    // Breadth-first: select the pane's agent, not agents launched by its tools.
    let level = [Number(root)];
    const seen = new Set<number>();
    while (level.length) {
        const matches = procs.filter(p => level.includes(p.pid) && p.agent === agent);
        if (matches.length) return matches.length === 1 ? matches[0]! : null;
        level.forEach(pid => seen.add(pid));
        level = procs.filter(p => level.includes(p.parent) && !seen.has(p.pid)).map(p => p.pid);
    }
    return null;
}
function sessionFile(agent: string, output: string): string | null {
    const files = [...new Set(output.split('\n').filter(l => l.startsWith('n')).map(l => l.slice(1)).filter(file =>
        agent === 'codex' ? /\/rollout-[^/]+\.jsonl$/.test(file) : /\/session-state\/[^/]+\/events\.jsonl$/.test(file)))];
    return files.length === 1 ? files[0]! : null;
}
async function copilotProcessState(output: string, pid: number): Promise<(AgentState & { file: string | null }) | null> {
    // Copilot closes events.jsonl between writes, but keeps its own process log
    // open. Resolve only that PID's log and its latest foreground registration.
    const files = [...new Set(output.split('\n').filter(l => l.startsWith('n')).map(l => l.slice(1))
        .filter(file => path.basename(path.dirname(file)) === 'logs'
            && new RegExp(`^process-\\d+-${Number(pid)}\\.log$`).test(path.basename(file))))];
    const log = files[0];
    if (files.length !== 1 || !log) return null;
    try {
        const state = await sessionState('copilot-process', log);
        return { ...state, file: state.sessionId ? path.join(path.dirname(log), '..', 'session-state', state.sessionId, 'events.jsonl') : null };
    } catch { return null; }
}
async function copilotSessionFile(output: string, pid: number): Promise<string | null> {
    return (await copilotProcessState(output, pid))?.file ?? null;
}
function modelEvent(agent: string, event: any, previous: string | null): string | null {
    if (agent === 'codex' && event.type === 'turn_context') return event.payload?.model || null;
    if (agent === 'copilot' && event.type === 'session.model_change') return event.data?.newModel || null;
    // Auxiliary calls can use another model: do not use model.turn_started.
    return previous;
}
async function sessionState(agent: string, file: string): Promise<AgentState> {
    const stat = fs.statSync(file);
    const key = `${agent}:${file}`;
    const version = `${stat.ino}:${stat.size}:${stat.mtimeMs}`;
    const cached = transcriptCache.get(key);
    if (cached?.version === version) return cached.state;
    // Logs are append-only. Resume at the last complete newline, so a partially
    // written JSON record (including split UTF-8 bytes) is retried next time.
    const append = cached && cached.ino === stat.ino && stat.size > cached.size;
    let offset = append ? cached.offset : 0;
    const state: AgentState = append ? { ...cached.state } : {
        model: null, id: agent === 'codex' ? path.basename(file, '.jsonl') : path.basename(path.dirname(file)),
    };
    const start = offset;
    const input = stat.size > start ? fs.createReadStream(file, { start, end: stat.size - 1 }) : null;
    let pending = Buffer.alloc(0);
    try {
        if (input) for await (const chunk of input as AsyncIterable<Buffer>) {
            pending = Buffer.concat([pending, chunk]);
            let newline: number;
            while ((newline = pending.indexOf(10)) !== -1) {
                const line = pending.subarray(0, newline);
                offset += newline + 1;
                pending = pending.subarray(newline + 1);
                if (agent === 'copilot-process') {
                    const text = line.toString('utf8');
                    const auth = text.match(/^\S+ \[INFO\] \[rust:copilot_runtime::managed_settings::api_session\] \[managedSettings\] self-fetch starting for account (.+)$/);
                    if (auth) {
                        const identity = auth[1]!.match(/^(https:\/\/[^/\s]+)\/([a-z0-9_-]+)$/i);
                        const account = identity ? { host: identity[1]!, login: identity[2]! } : null;
                        if (accountKey(account) !== accountKey(state.account)) state.accountEpoch = offset;
                        state.account = account;
                    }
                    const match = text.match(/^\S+ \[INFO\] (Registering|Unregistering) foreground session: ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s*$/i);
                    if (match?.[1] === 'Registering') state.sessionId = match[2];
                    else if (match && state.sessionId === match[2]) state.sessionId = null;
                    continue;
                }
                try {
                    const event = JSON.parse(line.toString('utf8'));
                    state.model = modelEvent(agent, event, state.model);
                    const limits = event.payload?.rate_limits;
                    if (agent === 'codex' && event.type === 'event_msg' && event.payload?.type === 'token_count'
                        && limits && (!limits.limit_id || limits.limit_id === 'codex')) state.rateLimits = limits;
                } catch {}
            }
        }
    } finally { input?.destroy(); }
    if (transcriptCache.size > 100) transcriptCache.clear();
    transcriptCache.set(key, { version, state, ino: stat.ino, size: stat.size, offset, bytesRead: stat.size - start });
    return state;
}
function codexUsage(limits: CodexRateLimits | undefined, now = Date.now() / 1000): string {
    const primary = limits?.primary;
    const used = primary?.used_percent;
    if (!Number.isFinite(used) || used === undefined || used < 0 || used > 100) return '';
    const reset = primary?.resets_at;
    // A passed reset makes this snapshot stale; wait for fresh server data.
    if (Number.isFinite(reset) && reset !== undefined && reset <= now) return '';
    let value = ` · ${Math.round(used)}%`;
    if (Number.isFinite(reset) && reset !== undefined) {
        const mins = Math.ceil((reset - now) / 60);
        value += ` · ${Math.floor(mins / 60)}h${mins % 60}m`;
    }
    return value;
}
function claudeValue(data: ClaudeHookData, now = Date.now() / 1000): string {
    const model = clean(data.model?.display_name || 'claude');
    for (const [key, label] of [['spend_limit', ' budget'], ['five_hour', ''], ['seven_day', ' week']] as const) {
        const limit = data.rate_limits?.[key];
        const used = limit?.used_percentage;
        const resets = limit?.resets_at;
        if (!Number.isFinite(used) || used === undefined || used < 0) continue;
        if (!Number.isFinite(resets) || resets === undefined || resets <= now) continue;
        const mins = Math.ceil((resets - now) / 60);
        const remaining = mins >= 1440 ? `${Math.floor(mins / 1440)}d${Math.floor(mins % 1440 / 60)}h`
            : `${Math.floor(mins / 60)}h${mins % 60}m`;
        return `${model} · ${Math.round(used)}%${label} · ${remaining}`;
    }
    return model;
}
function hook(data: ClaudeHookData): void {
    const procs = processes();
    let proc = procs.find(p => p.pid === process.ppid);
    const seen = new Set<number>();
    while (proc && proc.agent !== 'claude' && !seen.has(proc.pid)) {
        seen.add(proc.pid);
        const parent: number = proc.parent;
        proc = procs.find(p => p.pid === parent);
    }
    if (proc?.agent === 'claude') atomic(path.join(cacheDir, `claude-${proc.pid}.json`), JSON.stringify({
        start: proc.start,
        data: { model: data.model, rate_limits: data.rate_limits },
    }));
    const ctx = data.context_window?.used_percentage;
    process.stdout.write(claudeValue(data) + (Number.isFinite(ctx) && ctx !== undefined ? ` · ${Math.round(ctx)}% ctx` : ''));
}
/** Only these fields are read, so a test may supply rows without a start time. */
type ProcLike = { pid: number; parent: number; agent: string; start?: string };
export interface RefreshIO {
    run: (command: string, args: string[]) => string | Promise<string>;
    processes: () => ProcLike[] | Promise<ProcLike[]>;
    atomic?: (file: string, value: string) => void;
}
async function refresh(io: RefreshIO = { run: runAsync, processes: async () => processes(await runAsync('ps', ['-axo', 'pid=,ppid=,lstart=,comm='])), atomic }) {
    const panes = (await io.run('tmux', ['list-panes', '-a', '-F', '#{pid}|#{pane_pid}|#{pane_current_command}'])).trim().split('\n')
        .filter(pane => /\|(claude|codex|copilot)$/.test(pane));
    // No process scans, open-file queries or transcript reads while idle.
    if (!panes.length) return;
    const procs = await io.processes();
    const targets = panes.flatMap(pane => {
        const [server, root, agent] = pane.split('|');
        if (!server || !root || !agent || !/^\d+$/.test(server) || !/^\d+$/.test(root)) return [];
        const proc = findAgent(procs, root, agent);
        if (process.argv.includes('--verbose')) process.stdout.write(JSON.stringify({ pane, proc, processCount: procs.length }) + '\n');
        return [{ server, root, agent, proc }];
    });
    const pids = [...new Set(targets.flatMap(t => t.proc && t.agent !== 'claude' ? [t.proc.pid] : []))];
    // One asynchronous, time-bounded lsof scan for every relevant PID: adding
    // panes cannot multiply the timeout or spawn an unbounded number of children.
    const filesPromise: Promise<Map<number, string>> = pids.length
        ? Promise.resolve(io.run('lsof', ['-a', '-p', pids.join(','), '-Fn'])).then(openFilesByPid)
        : Promise.resolve(new Map());
    await Promise.allSettled(targets.map(async ({ server, root, agent, proc }) => {
        let value = agent;
        if (proc) {
            if (agent === 'claude') {
                const cached = readJSON(path.join(cacheDir, `claude-${proc.pid}.json`)) as
                    { start?: string; data?: ClaudeHookData } | null;
                if (cached?.data && cached.start === proc.start) value = claudeValue(cached.data);
            } else {
                const openFiles = (await filesPromise).get(proc.pid) || '';
                const copilot = agent === 'copilot' ? await copilotProcessState(openFiles, proc.pid) : null;
                const file = sessionFile(agent, openFiles)
                    || copilot?.file;
                if (process.argv.includes('--verbose')) process.stdout.write(JSON.stringify({ agent, file }) + '\n');
                if (file) {
                    try {
                        const state = await sessionState(agent, file);
                        value = state.model ? clean(state.model) : agent;
                        if (agent === 'codex') value += codexUsage(state.rateLimits);
                        if (agent === 'copilot') {
                            const home = path.dirname(path.dirname(path.dirname(file)));
                            value += quotaValue(copilotQuota(home, {
                                process: `${proc.pid}:${proc.start}:${copilot?.accountEpoch}`, account: copilot?.account,
                            }));
                        }
                    } catch { /* The session may exit while its log is read. */ }
                }
            }
        }
        (io.atomic || atomic)(path.join(cacheDir, `pane-${server}-${root}`), `${Math.floor(Date.now() / 1000)}\n${agent}\n${value}\n`);
    }));
}
const emojis = [...'🍎🍏🍐🍊🍋🍉🍇🍓🍒🥭🍍🥝🍅🌽🥕☕🍕🍩🍪🎂🧁🍰🥐🥯🥞🧇🍫🍬🍭🍯🥧🍞🍞🧀🥨🍦🍨🍿🍵🧃🧋🍮'];
const agentStyles: Record<string, boolean> = { claude: true, copilot: true, codex: true };
/** [pane_id, server pid, pane pid, command, cwd, is-active] — one tmux list-panes row. */
type PaneRow = [string, string, string, string, string, string];
// One publisher per watcher: shared directories are queried only once per tick,
// battery every 30s.
function createStatusPublisher(
    runCommand: RunCommand = runAsync,
    readRecord = (server: string, pane: string) => readAgentCache(cacheDir, server, pane),
    readBattery = battery,
) {
    let batteryAt = -Infinity;
    let batteryValue = '';
    return async (now = Date.now() / 1000): Promise<void> => {
        const rows = await runCommand('tmux', ['list-panes', '-a', '-F', '#{pane_id}\t#{pid}\t#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_active}']);
        const panes = rows.trimEnd().split('\n').map(row => row.split('\t'))
            .filter((row): row is PaneRow => row.length === 6 && /^%\d+$/.test(row[0]!));
        if (!panes.length) return;
        const branches = new Map<string, Promise<string>>();
        for (const [, , , , directory] of panes) {
            if (!branches.has(directory)) branches.set(directory, gitPill(directory, runCommand));
        }
        if (now - batteryAt >= 30) {
            batteryValue = await readBattery(runCommand);
            batteryAt = now;
        }
        const commands: string[][] = [];
        const set = (...args: string[]) => commands.push(['set-option', ...args]);
        let activePill = '';
        let activeBranch = '';
        for (const [id, server, root, agent, directory, active] of panes) {
            let record = '';
            if (agentStyles[agent] && /^\d+$/.test(server) && /^\d+$/.test(root)) {
                record = readRecord(server, root);
            }
            const agentValue = agentPill(agent, record, now);
            const branchValue = (await branches.get(directory)) ?? '';
            if (active === '1') { activePill = agentValue; activeBranch = branchValue; }
            for (const [key, value] of Object.entries({
                agent, directory, 'agent-pill': agentValue,
                'git-pill': branchValue,
            })) set('-p', '-t', id, `@initd-${key}`, value);
        }
        // status-right is global; publish the currently active pane's values
        // there as well as pane-scoped values used by callers inspecting panes.
        set('-g', '@initd-agent-pill', activePill);
        set('-g', '@initd-git-pill', activeBranch);
        set('-g', '@initd-battery', batteryValue ? pill('\u{f0079}', batteryValue, '#4ec994') : '');
        const windows = (await runCommand('tmux', ['list-windows', '-a', '-F', '#{window_id} #{@emoji}'])).trim().split('\n').map(line => line.split(' '));
        const used = new Set(windows.map(([, emoji]) => emoji));
        for (const [id, existing] of windows) {
            if (!/^@\d+$/.test(id) || emojis.includes(existing)) continue;
            const available = emojis.filter(emoji => !used.has(emoji));
            const choices = available.length ? available : emojis;
            const emoji = choices[Math.floor(Math.random() * choices.length)];
            used.add(emoji);
            set('-w', '-t', id, '@emoji', emoji);
        }
        for (const args of commands) await runCommand('tmux', args);
    };
}
function status() {
    let row;
    try {
        row = run('tmux', ['display-message', '-p', '#{pid}|#{pane_pid}|#{pane_current_command}']).trim().split('|');
    } catch { return ''; }
    const [server, pane, agent] = row;
    if (!/^\d+$/.test(server) || !/^\d+$/.test(pane)) return '';
    const record = readAgentCache(cacheDir, server, pane);
    if (!record) return '';
    return agentPill(agent, record);
}
async function main() {
    if (process.argv[2] === 'hook') {
        try { hook(JSON.parse(fs.readFileSync(0, 'utf8'))); } catch {}
        return;
    }
    if (process.argv[2] === 'status') {
        process.stdout.write(status());
        return;
    }
    if (!['watch', 'once'].includes(process.argv[2])) {
        console.error('Usage: tmux.ts <watch|once|status|hook>');
        process.exitCode = 1;
        return;
    }
    const publish = createStatusPublisher();
    process.stdout.on('error', () => process.exit(0)); // tmux closed its job pipe
    do {
        try { await refresh(); } catch {}
        try { await publish(); } catch {}
        if (process.argv[2] === 'once') return;
        process.stdout.write('\n');
        await new Promise(resolve => setTimeout(resolve, STATUS_REFRESH_MS));
        // tmux restarts the same #() job on its next redraw. Source changes take
        // effect without changing the job key or leaving old worker versions alive.
        if (sourceVersion() !== loadedVersion) return;
    } while (true);
}
export { findAgent, sessionFile, copilotSessionFile, copilotProcessState, modelEvent, sessionState, claudeValue, codexUsage, atomic, refresh, openFilesByPid, createStatusPublisher, status, hook };
let invokedDirectly = false;
try { invokedDirectly = Boolean(process.argv[1]) && fs.realpathSync(process.argv[1]) === filename; } catch {}
if (invokedDirectly) main();
