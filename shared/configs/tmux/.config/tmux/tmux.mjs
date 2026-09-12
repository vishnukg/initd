// Bind status to the pane's process and its open transcript, never log recency.
import fs from 'node:fs';
import path from 'node:path';
import { execFile, execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {
    agentPill, battery, clean, gitPill, pill, readAgentCache,
    claudeValue, codexUsage, codexLimit, copilotUsage,
} from './status-renderer.mjs';

// Process rows: { pid, parent, start, agent, command }.
// Transcript state: { model, id, autoModel?, rateLimits?, limit?, quota?, sessionId? }.
// External log formats can change. Unknown data leaves the agent icon visible;
// models and quotas must come from that pane's process and its open files.

const filename = fileURLToPath(import.meta.url);
const cacheDir = path.join(process.env.HOME, '.cache/initd-tmux');
// Match tmux's once-per-second redraw instead of scanning between redraws.
const STATUS_REFRESH_MS = 1000;
const transcriptCache = new Map();
const sourceVersion = () => [filename, fileURLToPath(new URL('./status-renderer.mjs', import.meta.url))]
    .map(file => fs.statSync(file).mtimeMs).join(':');
const loadedVersion = sourceVersion();
function run(command, args) {
    // ps lstart follows locale (e.g. "Sep 8" vs "8 Sep"); fix its wire format.
    try {
        return execFileSync(command, args, {
            encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' },
            timeout: 3000, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024,
            stdio: ['ignore', 'pipe', 'ignore'],
        });
    } catch {
        return '';
    }
}
function runAsync(command, args, checked = false) {
    // lsof may return 1 when one requested process has just exited, while
    // still returning complete records for the other processes.
    return new Promise((resolve, reject) => execFile(command, args, {
        encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' },
        timeout: 3000, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024,
    }, (error, stdout) => {
        if (error && checked) return reject(error);
        resolve(error && !(command === 'lsof' && error.code === 1) ? '' : stdout);
    }));
}
function openFilesByPid(output) {
    const files = new Map();
    let pid;
    for (const line of output.split('\n')) {
        if (/^p\d+$/.test(line)) {
            pid = Number(line.slice(1));
            files.set(pid, '');
        } else if (pid && line.startsWith('n')) {
            files.set(pid, files.get(pid) + line + '\n');
        }
    }
    return files;
}
function fileNames(output) {
    const names = output.split('\n')
        .filter(line => line.startsWith('n'))
        .map(line => line.slice(1));
    return [...new Set(names)];
}
function readJSON(file) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}
function atomic(file, value) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.${process.pid}.${randomUUID()}.tmp`;
    try {
        fs.writeFileSync(tmp, value, { mode: 0o600, flag: 'wx' });
        fs.renameSync(tmp, file);
    } finally {
        try { fs.unlinkSync(tmp); } catch { /* Already renamed or removed. */ }
    }
}
// Match both comm and argv[0]: Copilot may rename comm to MainThread, and
// macOS and Linux tmux differ in which name pane_current_command reports.
const PS_FORMAT = 'pid=,ppid=,lstart=,comm=,args=';
function processes(output = run('ps', ['-axo', PS_FORMAT])) {
    return output.trim().split('\n').flatMap(line => {
        const m = line.trim().match(/^(\d+)\s+(\d+)\s+(\S+\s+\S+\s+\d+\s+\S+\s+\d+)\s+(\S+)(?:\s+(.*))?$/);
        return m ? [{
            pid: Number(m[1]), parent: Number(m[2]), start: m[3],
            agent: path.basename(m[4]),
            command: m[5] ? path.basename(m[5].split(/\s/)[0]) : '',
        }] : [];
    });
}
// A row matches under either name; rows carrying only `agent` stay valid.
const named = (proc, agent) => proc.agent === agent || proc.command === agent;
// Only pid/parent/agent are read, so a caller may pass rows without a start time.
function findAgent(procs, root, agent) {
    // Breadth-first: select the pane's agent, not agents launched by its tools.
    let level = [Number(root)];
    const seen = new Set();
    while (level.length) {
        const matches = procs.filter(p => level.includes(p.pid) && named(p, agent));
        if (matches.length) return matches.length === 1 ? matches[0] : null;
        level.forEach(pid => seen.add(pid));
        level = procs.filter(p => level.includes(p.parent) && !seen.has(p.pid)).map(p => p.pid);
    }
    return null;
}
function sessionFile(agent, output) {
    const pattern = agent === 'codex' ? /\/rollout-[^/]+\.jsonl$/ : /\/session-state\/[^/]+\/events\.jsonl$/;
    const files = fileNames(output).filter(file => pattern.test(file));
    return files.length === 1 ? files[0] : null;
}
async function copilotProcessState(output, pid) {
    // Copilot closes events.jsonl between writes, but keeps its own process log
    // open. Resolve only that PID's log and its latest foreground registration.
    const pattern = new RegExp(`^process-\\d+-${Number(pid)}\\.log$`);
    const files = fileNames(output).filter(file => path.basename(path.dirname(file)) === 'logs'
        && pattern.test(path.basename(file)));
    if (files.length !== 1) return null;
    try {
        const state = await sessionState('copilot-process', files[0]);
        return { ...state, file: state.sessionId ? path.join(path.dirname(files[0]), '..', 'session-state', state.sessionId, 'events.jsonl') : null };
    } catch { return null; }
}
async function copilotSessionFile(output, pid) {
    return (await copilotProcessState(output, pid))?.file ?? null;
}
// Codex may not create a rollout until its first turn. Its open SQLite
// databases provide a fallback model; quotas still require transcript events.
let sqlite;
// Opened and closed per read: these are another process's live databases, and
// nothing here is hot enough to justify holding a handle across ticks.
async function readRows(file, sql, ...values) {
    // Hosts without node:sqlite retain transcript-only status.
    if (sqlite === undefined) sqlite = await import('node:sqlite').catch(() => null);
    if (!sqlite) return [];
    let db;
    try { db = new sqlite.DatabaseSync(file, { readOnly: true }); } catch { return []; }
    try { return db.prepare(sql).all(...values); } catch { return []; }
    finally { try { db.close(); } catch {} }
}
async function codexSqliteState(openFiles, proc) {
    const files = fileNames(openFiles);
    const newest = pattern => files.filter(file => pattern.test(file))
        .sort((a, b) => a.localeCompare(b, 'en', { numeric: true })).pop();
    const logs = newest(/\/logs_\d+\.sqlite$/);
    const state = newest(/\/state_\d+\.sqlite$/);
    if (!logs || !state) return null;
    // process_uuid is "pid:<pid>:<uuid>" and we know only the pid, which the
    // kernel reuses, so require the row to postdate this process's own start.
    const started = Date.parse(proc.start) / 1000;
    if (!Number.isFinite(started)) return null;
    // Logs contain both turn IDs and thread IDs. Only IDs present in threads
    // can identify a session; query them together and prefer the latest one.
    const since = Math.floor(started);
    const mine = `pid:${proc.pid}:%`;
    const candidates = await readRows(logs,
        'select thread_id, max(id) as last from logs where process_uuid like ? and thread_id is not null and ts >= ? group by thread_id order by last desc limit 200',
        mine, since);
    // One query for every candidate rather than one per candidate: the turn ids
    // just do not come back, and a session's turns are what makes the list long.
    const rows = candidates.length ? await readRows(state,
        `select id, model from threads where id in (${candidates.map(() => '?').join(',')})`,
        ...candidates.map(row => row.thread_id)) : [];
    const threads = new Map(rows.map(row => [row.id, row.model]));
    for (const { thread_id: thread } of candidates) {
        if (threads.has(thread) && threads.get(thread)) return { id: thread, model: threads.get(thread) };
    }
    // Before the first turn there may be no threads row. The session-init
    // message can name the initial model, but never overrides a threads row.
    const init = await readRows(logs,
        "select feedback_log_body as body from logs where process_uuid like ? and ts >= ? and feedback_log_body like '%Configuring session: model=%' order by id desc limit 1",
        mine, since);
    const model = String(init[0]?.body ?? '').match(/Configuring session: model=([^\s;]+)/)?.[1];
    // Reached only before the first turn, so every id logged so far came from
    // thread/start and the newest is the thread's own rather than a turn's.
    if (model) return { id: candidates[0]?.thread_id ?? null, model };
    // A thread known with no model anywhere is still worth reporting as known;
    // the caller keeps the bare agent name rather than inventing a model.
    for (const { thread_id: thread } of candidates) {
        if (threads.has(thread)) return { id: thread, model: null };
    }
    return null;
}
// Accept account-wide limits under either observed ID. Per-model limits and
// credit balances do not describe subscription usage.
const ACCOUNT_LIMIT_IDS = new Set(['codex', 'premium']);
// Apply only foreground model and quota events. Auxiliary model calls do not
// change the displayed model. Each recognized event updates the state in place.
function applyEvent(agent, state, event) {
    if (agent === 'codex') {
        if (event.type === 'turn_context') state.model = event.payload?.model || null;
        if (event.type !== 'event_msg') return;
        const payload = event.payload;
        switch (payload?.type) {
            case 'thread_settings_applied':
                state.model = payload.thread_settings?.model || state.model;
                break;
            case 'token_count': {
                const limits = payload.rate_limits;
                if (limits && (!limits.limit_id || ACCOUNT_LIMIT_IDS.has(limits.limit_id))) {
                    state.rateLimits = limits;
                }
                break;
            }
            case 'task_complete':
                // Any later completed turn clears an earlier limit notice.
                state.limit = payload.error?.codex_error_info === 'usage_limit_exceeded'
                    ? payload.error.message : null;
                break;
        }
    } else if (agent === 'copilot') {
        switch (event.type) {
            case 'session.model_change':
                state.model = event.data?.newModel || null;
                if (state.model !== 'auto') state.autoModel = null;
                break;
            case 'session.auto_mode_resolved':
                state.autoModel = event.data?.chosenModel || null;
                break;
            case 'model.model_call_success':
                if (event.data?.quotaSnapshots) state.quota = event.data;
                break;
        }
    }
}
// Only auto mode has something to resolve; a pinned model is already the answer,
// and a session that has not routed a turn yet has nothing better than the mode.
function modelName(agent, state) {
    if (agent === 'copilot' && state.model === 'auto' && state.autoModel) return state.autoModel;
    return state.model;
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
                    applyEvent(agent, state, JSON.parse(line.toString('utf8')));
                } catch { /* Ignore malformed records; later records may be valid. */ }
            }
        }
    } finally { input?.destroy(); }
    if (transcriptCache.size > 100) transcriptCache.clear();
    transcriptCache.set(key, { version, state, ino: stat.ino, size: stat.size, offset });
    return state;
}
function hook(data) {
    const procs = processes();
    let proc = procs.find(p => p.pid === process.ppid);
    const seen = new Set();
    while (proc && !named(proc, 'claude') && !seen.has(proc.pid)) {
        seen.add(proc.pid);
        proc = procs.find(p => p.pid === proc.parent);
    }
    if (proc && named(proc, 'claude')) atomic(path.join(cacheDir, `claude-${proc.pid}.json`), JSON.stringify({
        start: proc.start,
        data: { model: data.model, rate_limits: data.rate_limits },
    }));
    const ctx = data.context_window?.used_percentage;
    process.stdout.write(claudeValue(data) + (Number.isFinite(ctx) ? ` · ${Math.round(ctx)}% ctx` : ''));
}
async function readPanes(runCommand = runAsync) {
    const rows = await runCommand('tmux', ['list-panes', '-a', '-F', '#{pane_id}\t#{pid}\t#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_active}']);
    return rows.trimEnd().split('\n').map(row => row.split('\t'))
        .filter(row => row.length === 6 && /^%\d+$/.test(row[0]));
}
async function refresh(io = { run: runAsync, processes: async () => processes(await runAsync('ps', ['-axo', PS_FORMAT])), atomic }, snapshot) {
    const panes = (snapshot ?? await readPanes(io.run))
        .filter(([, , , agent]) => ['claude', 'codex', 'copilot'].includes(agent));
    // No process scans, open-file queries or transcript reads while idle.
    if (!panes.length) return;
    const procs = await io.processes();
    const targets = panes.flatMap(pane => {
        const [, server, root, agent] = pane;
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
                let model = null;
                let usage = '';
                if (file) {
                    try {
                        const state = await sessionState(agent, file);
                        model = modelName(agent, state);
                        if (agent === 'codex') usage = codexUsage(state.rateLimits) || codexLimit(state.limit);
                        if (agent === 'copilot') usage = copilotUsage(state.quota);
                    } catch { /* The session may exit while its log is read. */ }
                }
                // A rollout that exists but has recorded no turn_context names no
                // model either, so the database answers for both cases - not just
                // for the missing-rollout one. The quota is never in there.
                if (!model && agent === 'codex') {
                    model = (await codexSqliteState(openFiles, proc).catch(() => null))?.model || null;
                }
                value = (model ? clean(model) : agent) + usage;
            }
        }
        (io.atomic || atomic)(path.join(cacheDir, `pane-${server}-${root}`), `${Math.floor(Date.now() / 1000)}\n${agent}\n${value}\n`);
    }));
}
// Replace numeric defaults with the first free space-themed name. Keeping the
// rule here covers sessions created by Fish, tmux commands, and keybindings.
const sessionNames = ['nova', 'vega', 'io', 'sol', 'luna', 'mars',
    'lyra', 'titan', 'pluto', 'orion'];
const emojis = [...'🍎🍏🍐🍊🍋🍉🍇🍓🍒🥭🍍🥝🍅🌽🥕☕🍕🍩🍪🎂🧁🍰🥐🥯🥞🧇🍫🍬🍭🍯🥧🍞🍞🧀🥨🍦🍨🍿🍵🧃🧋🍮'];
// Each attached tmux client starts a watcher. One owner per socket publishes
// the shared pane options; followers idle and take over if the owner exits.
function watcherLockPath(socket) {
    return path.join(cacheDir, `watcher-${createHash('sha256').update(socket).digest('hex')}.lock`);
}
let lockPath = watcherLockPath((process.env.TMUX || 'default').replace(/,\d+,\d+$/, ''));
// A slow cycle is still owned work. Reclaim only after the owner exits; an
// elapsed-time lease could elect a second worker while a subprocess is pending.
function claimWatcherLock(now = Date.now(), io = {}) {
    const file = io.path || lockPath;
    // mkdir first: on a fresh machine nothing has written the cache directory
    // yet, and an ENOENT here would read as 'someone else holds it' and leave
    // every watcher idle with nobody publishing.
    const create = io.create || (value => {
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, value, { flag: 'wx', mode: 0o600 });
    });
    const read = io.read || (() => fs.readFileSync(file, 'utf8'));
    const remove = io.remove || (() => fs.unlinkSync(file));
    const alive = io.alive || (pid => {
        try { process.kill(pid, 0); return true; } catch (error) { return error.code === 'EPERM'; }
    });
    const me = io.pid || process.pid;
    const stamp = `${me}\n${now}\n`;
    // wx: whoever creates the file wins, so two watchers starting together
    // cannot both believe they own it.
    try { create(stamp); return true; } catch { /* someone holds it */ }
    let holder, created;
    try { [holder, created] = read().split('\n'); } catch { return false; }
    if (Number(holder) === me) return true;
    // Both fields are checked for shape rather than run through Number(), which
    // turns a truncated or half-written file into a plausible-looking 0 instead
    // of rejecting it. An unreadable lock must not block the work forever.
    const owned = /^\d+$/.test(holder || '') && /^\d+$/.test(created || '')
        && alive(Number(holder));
    if (owned) return false;
    try { remove(); } catch { /* a peer reclaimed it first */ }
    try { create(stamp); return true; } catch { return false; }
}
function releaseWatcherLock(io = {}) {
    const file = io.path || lockPath;
    const read = io.read || (() => fs.readFileSync(file, 'utf8'));
    const remove = io.remove || (() => fs.unlinkSync(file));
    const me = io.pid || process.pid;
    // Only ever drop our own: followers must leave the owner alone.
    try { if (Number(read().split('\n')[0]) !== me) return false; } catch { return false; }
    try { remove(); return true; } catch { return false; }
}
// Remove stale pane/agent caches, preserving other live servers and locks.
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
        if (name === 'watcher.lock' || /^watcher-[a-f0-9]{64}\.lock$/.test(name)) continue;
        const pane = name.match(/^pane-(\d+)-(\d+)$/);
        const claude = name.match(/^claude-(\d+)\.json$/);
        let dead = true;
        if (pane) {
            dead = pane[1] === server ? !livePanes.has(pane[2]) : !alive(Number(pane[1]));
        } else if (claude) {
            dead = !alive(Number(claude[1]));
        }
        if (!dead) continue;
        try { remove(name); removed.push(name); } catch { /* raced another sweep */ }
    }
    return removed;
}
// Agent values remain responsive; Git is cached for 3s, naming and battery for
// 30s. Creation hooks run their own first publish immediately.
function createStatusPublisher(runCommand = runAsync, readRecord = (server, pane) => readAgentCache(cacheDir, server, pane), readBattery = battery, sweep = sweepCache) {
    let batteryAt = -Infinity;
    let batteryValue = '';
    let sweptAt = -Infinity;
    let namesAt = -Infinity;
    const branches = new Map();
    let published = new Map();
    return async (now = Date.now() / 1000, snapshot) => {
        const panes = snapshot ?? await readPanes(runCommand);
        if (!panes.length) return;
        const directories = new Set(panes.map(row => row[4]));
        for (const directory of branches.keys()) {
            if (!directories.has(directory)) branches.delete(directory);
        }
        for (const directory of directories) {
            if (!branches.has(directory) || now - branches.get(directory).at >= 3) {
                branches.set(directory, { at: now, value: gitPill(directory, runCommand) });
            }
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
        const nextPublished = new Map();
        const set = (...args) => {
            const key = JSON.stringify(args.slice(0, -1));
            const value = args.at(-1);
            nextPublished.set(key, value);
            if (published.get(key) !== value) commands.push(['set-option', ...args]);
        };
        let activePill = '';
        let activeBranch = '';
        for (const [id, server, root, agent, directory, active] of panes) {
            let record = '';
            if (['claude', 'copilot', 'codex'].includes(agent) && /^\d+$/.test(server) && /^\d+$/.test(root)) {
                record = readRecord(server, root);
            }
            const agentValue = agentPill(agent, record, now);
            const branchValue = await branches.get(directory).value;
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
        const checkNames = now - namesAt >= 30;
        if (checkNames) {
            const windows = (await runCommand('tmux', ['list-windows', '-a', '-F', '#{window_id} #{@emoji}'])).trim().split('\n').map(line => line.split(' '));
            const used = new Set(windows.map(([, emoji]) => emoji));
            for (const [id, existing] of windows) {
                if (!/^@\d+$/.test(id) || emojis.includes(existing)) continue;
                const available = emojis.filter(emoji => !used.has(emoji));
                const choices = available.length ? available : emojis;
                const emoji = choices[Math.floor(Math.random() * choices.length)];
                used.add(emoji);
                commands.push(['set-option', '-w', '-t', id, '@emoji', emoji]);
            }
            const sessions = (await runCommand('tmux', ['list-sessions', '-F', '#{session_id} #{session_name}']))
                .split('\n').filter(Boolean).map(line => {
                    const separator = line.indexOf(' ');
                    return [line.slice(0, separator), line.slice(separator + 1)];
                });
            const takenNames = new Set(sessions.map(([, name]) => name));
            for (const [id, name] of sessions) {
                // Treat numeric names as allocated defaults; preserve other names.
                if (!/^\$\d+$/.test(id) || !/^\d+$/.test(name)) continue;
                const free = sessionNames.find(candidate => !takenNames.has(candidate));
                if (!free) break;
                takenNames.add(free);
                // Not a set-option, so it is pushed rather than going through set().
                commands.push(['rename-session', '-t', id, free]);
            }
        }
        // One tmux invocation for the whole tick, as a command sequence. Three
        // panes is 18 option changes, and a process each is the bulk of a
        // publish. Only a standalone ';' argument separates commands, so an
        // embedded one ("feature;wip") passes through untouched; a value that is
        // exactly ';' is escaped, which tmux also rejects when sent on its own.
        if (commands.length) await runCommand('tmux', commands.flatMap((args, index) =>
            (index ? [';'] : []).concat(args.map(arg => arg === ';' ? '\\;' : arg))), true);
        // Commit only after tmux accepts the batch, so a failed write is retried.
        published = nextPublished;
        if (checkNames) namesAt = now;
    };
}
async function main() {
    if (!['watch', 'once'].includes(process.argv[2])) {
        console.error('Usage: tmux.mjs <watch|once>');
        process.exitCode = 1;
        return;
    }
    const publish = createStatusPublisher();
    // `once` is the after-new-window/after-new-session hook and runs alone, so
    // it never defers to the lock - a new window would otherwise wait out a tick
    // for its emoji.
    const watching = process.argv[2] === 'watch';
    if (watching) {
        const socket = run('tmux', ['display-message', '-p', '#{socket_path}']).trim();
        if (!socket) return;
        lockPath = watcherLockPath(socket);
    }
    process.stdout.on('error', () => process.exit(0)); // tmux closed its job pipe
    process.on('exit', () => { if (watching) releaseWatcherLock(); });
    do {
        if (!watching || claimWatcherLock()) {
            const panes = await readPanes();
            try { await refresh(undefined, panes); } catch {}
            try { await publish(undefined, panes); } catch {}
        }
        if (!watching) return;
        // Blank by design: the pills are read from the @initd-* options, not
        // from this job's output. The write is what keeps tmux's pipe alive.
        process.stdout.write('\n');
        await new Promise(resolve => setTimeout(resolve, STATUS_REFRESH_MS));
        // tmux restarts the same #() job on its next redraw. Source changes take
        // effect without changing the job key or leaving old worker versions alive.
        if (sourceVersion() !== loadedVersion) return;
    } while (true);
}
export {
    processes, findAgent, sessionFile, copilotSessionFile, sessionState,
    codexSqliteState, modelName, atomic, refresh, openFilesByPid,
    createStatusPublisher, hook, claimWatcherLock, releaseWatcherLock,
    sweepCache, lockPath, watcherLockPath,
};
let invokedDirectly = false;
try { invokedDirectly = Boolean(process.argv[1]) && fs.realpathSync(process.argv[1]) === filename; } catch {}
if (invokedDirectly) main();
