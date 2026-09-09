// Bind status to the pane's process and its open transcript, never log recency.
import fs from 'node:fs';
import path from 'node:path';
import { execFile, execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { agentPill, battery, clean, gitPill, pill, readAgentCache } from './status-renderer.mjs';

// The shapes below are reverse-engineered from three agents' logs; none are
// documented and all can change without notice.
//   proc         one `ps -axo pid=,ppid=,lstart=,comm=` row:
//                { pid, parent, start, agent }
//   state        accumulated while replaying an append-only transcript:
//                { model, id, rateLimits?, quota?, sessionId? }
//   rateLimits   Codex token_count payload:
//                { limit_id, primary: { used_percent, resets_at } }
//   quota        Copilot model.model_call_success payload, i.e. event.data:
//                { quotaSnapshots: { chat|completions|premium_interactions:
//                  { entitlementRequests, remainingPercentage, resetDate,
//                    isUnlimitedEntitlement, hasQuota?, tokenBasedBilling? } } }
//   hook data    what Claude Code pipes into the statusLine hook on stdin:
//                { model: { id, display_name },
//                  rate_limits: { spend_limit|five_hour|seven_day:
//                                 { used_percentage, resets_at } },
//                  context_window: { used_percentage } }
//   pane row     tmux list-panes -F, tab separated:
//                [pane_id, server pid, pane pid, command, cwd, active]

const filename = fileURLToPath(import.meta.url);
const cacheDir = path.join(process.env.HOME, '.cache/initd-tmux');
// How often pane options are refreshed. tmux repaints on status-interval, whose
// floor is one whole second, so this only bounds how stale a value can be when
// that repaint happens - it cannot make the bar paint faster. Halving it to
// 500ms costs ~1.7% -> ~3.2% of one core; a cycle itself is ~85ms.
const STATUS_REFRESH_MS = 500;
const transcriptCache = new Map();
const sourceVersion = () => [filename, fileURLToPath(new URL('./status-renderer.mjs', import.meta.url))]
    .map(file => fs.statSync(file).mtimeMs).join(':');
const loadedVersion = sourceVersion();
function run(command, args) {
    // ps lstart follows locale (e.g. "Sep 8" vs "8 Sep"); fix its wire format.
    try { return execFileSync(command, args, { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' }, timeout: 3000, maxBuffer: 8 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] }); }
    catch { return ''; }
}
function runAsync(command, args) {
    // lsof may return 1 when one requested process has just exited, while
    // still returning complete records for the other processes.
    return new Promise(resolve => execFile(command, args, {
        encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' },
        timeout: 3000, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024,
    }, (error, stdout) => resolve(error && !(command === 'lsof' && error.code === 1) ? '' : stdout)));
}
function openFilesByPid(output) {
    const files = new Map();
    let pid;
    for (const line of output.split('\n')) {
        if (/^p\d+$/.test(line)) { pid = Number(line.slice(1)); files.set(pid, ''); }
        else if (pid && line.startsWith('n')) files.set(pid, files.get(pid) + line + '\n');
    }
    return files;
}
function readJSON(file) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}
function atomic(file, value) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.${process.pid}.${randomUUID()}.tmp`;
    try { fs.writeFileSync(tmp, value, { mode: 0o600 }); fs.renameSync(tmp, file); }
    finally { try { fs.unlinkSync(tmp); } catch {} }
}
function processes(output = run('ps', ['-axo', 'pid=,ppid=,lstart=,comm='])) {
    return output.trim().split('\n').flatMap(line => {
        const m = line.trim().match(/^(\d+)\s+(\d+)\s+(\S+\s+\S+\s+\d+\s+\S+\s+\d+)\s+(.+)$/);
        return m ? [{ pid: Number(m[1]), parent: Number(m[2]), start: m[3], agent: path.basename(m[4]) }] : [];
    });
}
// Only pid/parent/agent are read, so a caller may pass rows without a start time.
function findAgent(procs, root, agent) {
    // Breadth-first: select the pane's agent, not agents launched by its tools.
    let level = [Number(root)];
    const seen = new Set();
    while (level.length) {
        const matches = procs.filter(p => level.includes(p.pid) && p.agent === agent);
        if (matches.length) return matches.length === 1 ? matches[0] : null;
        level.forEach(pid => seen.add(pid));
        level = procs.filter(p => level.includes(p.parent) && !seen.has(p.pid)).map(p => p.pid);
    }
    return null;
}
function sessionFile(agent, output) {
    const files = [...new Set(output.split('\n').filter(l => l.startsWith('n')).map(l => l.slice(1)).filter(file =>
        agent === 'codex' ? /\/rollout-[^/]+\.jsonl$/.test(file) : /\/session-state\/[^/]+\/events\.jsonl$/.test(file)))];
    return files.length === 1 ? files[0] : null;
}
async function copilotProcessState(output, pid) {
    // Copilot closes events.jsonl between writes, but keeps its own process log
    // open. Resolve only that PID's log and its latest foreground registration.
    const files = [...new Set(output.split('\n').filter(l => l.startsWith('n')).map(l => l.slice(1))
        .filter(file => path.basename(path.dirname(file)) === 'logs'
            && new RegExp(`^process-\\d+-${Number(pid)}\\.log$`).test(path.basename(file))))];
    if (files.length !== 1) return null;
    try {
        const state = await sessionState('copilot-process', files[0]);
        return { ...state, file: state.sessionId ? path.join(path.dirname(files[0]), '..', 'session-state', state.sessionId, 'events.jsonl') : null };
    } catch { return null; }
}
async function copilotSessionFile(output, pid) {
    return (await copilotProcessState(output, pid))?.file ?? null;
}
// Account-wide limits, as opposed to a per-model one that must not overwrite
// them. Codex renamed this from "codex" to "premium" around 2026-09-08; across
// 621 token_count events these are the only two ids ever seen, so the guard was
// only ever excluding the rename. The premium payload reports primary and
// secondary null, i.e. no usage at all, so the pill renders a blank quota - it
// is accepted anyway so it resumes on its own once those fields are populated.
//
// Do NOT read credits.has_credits as "out of quota" to fill that blank. It is
// {has_credits: false, unlimited: false, balance: "0"} on all 615 older events
// too, the ones reporting 3% and 98% used - it means this plan does not use the
// credits mechanism, not that anything is exhausted. There is likewise no reset
// time anywhere in the premium payload, so "none left until HH:MM" cannot be
// rendered either. Blank is the only truthful output.
const ACCOUNT_LIMIT_IDS = new Set(['codex', 'premium']);
function modelEvent(agent, event, previous) {
    if (agent === 'codex' && event.type === 'turn_context') return event.payload?.model || null;
    if (agent === 'copilot' && event.type === 'session.model_change') return event.data?.newModel || null;
    // Auxiliary calls can use another model: do not use model.turn_started.
    return previous;
}
async function sessionState(agent, file) {
    const stat = fs.statSync(file);
    const key = `${agent}:${file}`;
    const version = `${stat.ino}:${stat.size}:${stat.mtimeMs}`;
    const cached = transcriptCache.get(key);
    if (cached?.version === version) return cached.state;
    // Logs are append-only. Resume at the last complete newline, so a partially
    // written JSON record (including split UTF-8 bytes) is retried next time.
    const append = cached && cached.ino === stat.ino && stat.size > cached.size;
    let offset = append ? cached.offset : 0;
    const state = append ? { ...cached.state } : {
        model: null, id: agent === 'codex' ? path.basename(file, '.jsonl') : path.basename(path.dirname(file)),
    };
    const start = offset;
    const input = stat.size > start ? fs.createReadStream(file, { start, end: stat.size - 1 }) : null;
    let pending = Buffer.alloc(0);
    try {
        if (input) for await (const chunk of input) {
            pending = Buffer.concat([pending, chunk]);
            let newline;
            while ((newline = pending.indexOf(10)) !== -1) {
                const line = pending.subarray(0, newline);
                offset += newline + 1;
                pending = pending.subarray(newline + 1);
                if (agent === 'copilot-process') {
                    const text = line.toString('utf8');
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
                        && limits && (!limits.limit_id || ACCOUNT_LIMIT_IDS.has(limits.limit_id))) state.rateLimits = limits;
                    if (agent === 'copilot' && event.type === 'model.model_call_success'
                        && event.data?.quotaSnapshots) state.quota = event.data;
                } catch {}
            }
        }
    } finally { input?.destroy(); }
    if (transcriptCache.size > 100) transcriptCache.clear();
    transcriptCache.set(key, { version, state, ino: stat.ino, size: stat.size, offset, bytesRead: stat.size - start });
    return state;
}
function codexUsage(limits, now = Date.now() / 1000) {
    const primary = limits?.primary;
    if (!Number.isFinite(primary?.used_percent) || primary.used_percent < 0 || primary.used_percent > 100) return '';
    const reset = primary.resets_at;
    // A passed reset makes this snapshot stale; wait for fresh server data.
    if (Number.isFinite(reset) && reset <= now) return '';
    let value = ` · ${Math.round(primary.used_percent)}%`;
    if (Number.isFinite(reset)) {
        const mins = Math.ceil((reset - now) / 60);
        value += ` · ${Math.floor(mins / 60)}h${mins % 60}m`;
    }
    return value;
}
// Copilot writes its own quota into the transcript we already read, so this is
// pure formatting - no RPC, no cache, no account binding. Because the snapshot
// comes from that session's own log it is inherently the right account, and it
// is refreshed whenever a model call happens, which is the only time the
// numbers move. A session that has not called a model yet has none, and the
// pill correctly shows just the model until it does.
function copilotUsage(data, now = Date.now() / 1000) {
    const snapshots = data?.quotaSnapshots;
    for (const key of ['premium_interactions', 'chat']) {
        const quota = snapshots?.[key];
        if (!quota || quota.hasQuota === false) continue;
        const label = quota.tokenBasedBilling ? 'credits' : key === 'chat' ? 'chat' : 'requests';
        if (quota.isUnlimitedEntitlement || quota.entitlementRequests === -1) return ` · ${label} ∞`;
        if (!(quota.entitlementRequests > 0) || !Number.isFinite(quota.remainingPercentage)) continue;
        if (quota.remainingPercentage < 0 || quota.remainingPercentage > 100) continue;
        let value = ` · ${Math.round(100 - quota.remainingPercentage)}% ${label}`;
        const reset = Date.parse(quota.resetDate) / 1000;
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
function claudeValue(data, now = Date.now() / 1000) {
    const model = clean(data.model?.display_name || 'claude');
    for (const [key, label] of [['spend_limit', ' budget'], ['five_hour', ''], ['seven_day', ' week']]) {
        const limit = data.rate_limits?.[key];
        if (!Number.isFinite(limit?.used_percentage) || limit.used_percentage < 0) continue;
        if (!Number.isFinite(limit.resets_at) || limit.resets_at <= now) continue;
        const mins = Math.ceil((limit.resets_at - now) / 60);
        const remaining = mins >= 1440 ? `${Math.floor(mins / 1440)}d${Math.floor(mins % 1440 / 60)}h`
            : `${Math.floor(mins / 60)}h${mins % 60}m`;
        return `${model} · ${Math.round(limit.used_percentage)}%${label} · ${remaining}`;
    }
    return model;
}
function hook(data) {
    const procs = processes();
    let proc = procs.find(p => p.pid === process.ppid);
    const seen = new Set();
    while (proc && proc.agent !== 'claude' && !seen.has(proc.pid)) {
        seen.add(proc.pid);
        proc = procs.find(p => p.pid === proc.parent);
    }
    if (proc?.agent === 'claude') atomic(path.join(cacheDir, `claude-${proc.pid}.json`), JSON.stringify({
        start: proc.start,
        data: { model: data.model, rate_limits: data.rate_limits },
    }));
    const ctx = data.context_window?.used_percentage;
    process.stdout.write(claudeValue(data) + (Number.isFinite(ctx) ? ` · ${Math.round(ctx)}% ctx` : ''));
}
async function refresh(io = { run: runAsync, processes: async () => processes(await runAsync('ps', ['-axo', 'pid=,ppid=,lstart=,comm='])), atomic }) {
    const panes = (await io.run('tmux', ['list-panes', '-a', '-F', '#{pid}|#{pane_pid}|#{pane_current_command}'])).trim().split('\n')
        .filter(pane => /\|(claude|codex|copilot)$/.test(pane));
    // No process scans, open-file queries or transcript reads while idle.
    if (!panes.length) return;
    const procs = await io.processes();
    const targets = panes.flatMap(pane => {
        const [server, root, agent] = pane.split('|');
        if (!/^\d+$/.test(server) || !/^\d+$/.test(root)) return [];
        const proc = findAgent(procs, root, agent);
        if (process.argv.includes('--verbose')) process.stdout.write(JSON.stringify({ pane, proc, processCount: procs.length }) + '\n');
        return [{ server, root, agent, proc }];
    });
    const pids = [...new Set(targets.filter(t => t.proc && t.agent !== 'claude').map(t => t.proc.pid))];
    // One asynchronous, time-bounded lsof scan for every relevant PID: adding
    // panes cannot multiply the timeout or spawn an unbounded number of children.
    const filesPromise = pids.length
        ? Promise.resolve(io.run('lsof', ['-a', '-p', pids.join(','), '-Fn'])).then(openFilesByPid)
        : Promise.resolve(new Map());
    await Promise.allSettled(targets.map(async ({ server, root, agent, proc }) => {
        let value = agent;
        if (proc) {
            if (agent === 'claude') {
                const cached = readJSON(path.join(cacheDir, `claude-${proc.pid}.json`));
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
                        if (agent === 'copilot') value += copilotUsage(state.quota);
                    } catch { /* The session may exit while its log is read. */ }
                }
            }
        }
        (io.atomic || atomic)(path.join(cacheDir, `pane-${server}-${root}`), `${Math.floor(Date.now() / 1000)}\n${agent}\n${value}\n`);
    }));
}
const emojis = [...'🍎🍏🍐🍊🍋🍉🍇🍓🍒🥭🍍🥝🍅🌽🥕☕🍕🍩🍪🎂🧁🍰🥐🥯🥞🧇🍫🍬🍭🍯🥧🍞🍞🧀🥨🍦🍨🍿🍵🧃🧋🍮'];
const agentStyles = { claude: true, copilot: true, codex: true };
// This cache directory is ours alone, so anything in it that no longer backs a
// live pane or agent is garbage - including files left by earlier versions of
// this script, which is why an unrecognised name counts as dead. Panes owned by
// another tmux server are swept only once that server itself is gone, since this
// one cannot enumerate another's panes.
function sweepCache(server, livePanes, io = {}) {
    const alive = io.alive || (pid => {
        try { process.kill(pid, 0); return true; } catch (error) { return error.code === 'EPERM'; }
    });
    let names;
    try { names = (io.readdir || (() => fs.readdirSync(cacheDir)))(); } catch { return []; }
    const remove = io.remove || (name => fs.unlinkSync(path.join(cacheDir, name)));
    const removed = [];
    for (const name of names) {
        if (name.endsWith('.tmp')) continue; // an atomic write in flight
        const pane = name.match(/^pane-(\d+)-(\d+)$/);
        const claude = name.match(/^claude-(\d+)\.json$/);
        const dead = pane ? (pane[1] === server ? !livePanes.has(pane[2]) : !alive(Number(pane[1])))
            : claude ? !alive(Number(claude[1]))
                : true;
        if (!dead) continue;
        try { remove(name); removed.push(name); } catch { /* raced another sweep */ }
    }
    return removed;
}
// One publisher per watcher: shared directories are queried only once per tick,
// battery every 30s.
function createStatusPublisher(runCommand = runAsync, readRecord = (server, pane) => readAgentCache(cacheDir, server, pane), readBattery = battery, sweep = sweepCache) {
    let batteryAt = -Infinity;
    let batteryValue = '';
    let sweptAt = -Infinity;
    return async (now = Date.now() / 1000) => {
        const rows = await runCommand('tmux', ['list-panes', '-a', '-F', '#{pane_id}\t#{pid}\t#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_active}']);
        const panes = rows.trimEnd().split('\n').map(row => row.split('\t'))
            .filter(row => row.length === 6 && /^%\d+$/.test(row[0]));
        if (!panes.length) return;
        const branches = new Map();
        for (const [, , , , directory] of panes) {
            if (!branches.has(directory)) branches.set(directory, gitPill(directory, runCommand));
        }
        if (now - batteryAt >= 30) {
            batteryValue = await readBattery(runCommand);
            batteryAt = now;
        }
        if (now - sweptAt >= 60) {
            sweep(panes[0][1], new Set(panes.map(([, , root]) => root)));
            sweptAt = now;
        }
        const commands = [];
        const set = (...args) => commands.push(['set-option', ...args]);
        let activePill = '';
        let activeBranch = '';
        for (const [id, server, root, agent, directory, active] of panes) {
            let record = '';
            if (agentStyles[agent] && /^\d+$/.test(server) && /^\d+$/.test(root)) {
                record = readRecord(server, root);
            }
            const agentValue = agentPill(agent, record, now);
            const branchValue = await branches.get(directory);
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
        // Redraw once the options are in place. Without this the bar would only
        // repaint on status-interval, which tmux caps at whole seconds. Pushed
        // directly: it is a command in its own right, not a set-option.
        // One tmux invocation for the whole tick, as a command sequence. Three
        // panes is 18 option changes, and a process each is the bulk of a
        // publish. Only a standalone ';' argument separates commands, so an
        // embedded one ("feature;wip") passes through untouched; a value that is
        // exactly ';' is escaped, which tmux also rejects when sent on its own.
        await runCommand('tmux', commands.flatMap((args, index) =>
            (index ? [';'] : []).concat(args.map(arg => arg === ';' ? '\\;' : arg))));
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
        console.error('Usage: tmux.mjs <watch|once|status|hook>');
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
export { findAgent, sessionFile, copilotSessionFile, copilotProcessState, modelEvent, sessionState, claudeValue, codexUsage, copilotUsage, atomic, refresh, openFilesByPid, createStatusPublisher, status, hook };
let invokedDirectly = false;
try { invokedDirectly = Boolean(process.argv[1]) && fs.realpathSync(process.argv[1]) === filename; } catch {}
if (invokedDirectly) main();
