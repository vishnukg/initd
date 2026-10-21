// Bind status to the pane's own agent process, never log recency.
import fs from 'node:fs';
import path from 'node:path';
import { execFile, execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {
    agentPill, battery, gitPill, pill, readAgentCache, claudeValue, agyValue,
} from './status-renderer.mjs';

// Process rows: { pid, parent, start, agent, command }.
// The model and quota come from the agent's own status-line hook, cached per
// agent process; anything unknown leaves the agent icon visible.

// Keyed by pane_current_command: each agent's renderer, and the payload keys
// its hook caches. Both payloads share Claude's shape apart from the quota.
const AGENTS = {
    claude: { value: claudeValue, keys: ['model', 'rate_limits'] },
    agy: { value: agyValue, keys: ['model', 'quota'] },
};

const filename = fileURLToPath(import.meta.url);
const cacheDir = path.join(process.env.HOME, '.cache/initd-tmux');
// Match tmux's once-per-second redraw instead of scanning between redraws.
const STATUS_REFRESH_MS = 1000;
// A hung ps/git must not stall the status line. Tests raise this: under a
// loaded parallel suite even a fake one-line `ps` can take longer than 3s.
const COMMAND_TIMEOUT_MS = Number(process.env.INITD_COMMAND_TIMEOUT_MS) || 3000;
const sourceVersion = () => [filename, fileURLToPath(new URL('./status-renderer.mjs', import.meta.url))]
    .map(file => fs.statSync(file).mtimeMs).join(':');
const loadedVersion = sourceVersion();
function run(command, args) {
    // ps lstart follows locale (e.g. "Sep 8" vs "8 Sep"); fix its wire format.
    try {
        return execFileSync(command, args, {
            encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' },
            timeout: COMMAND_TIMEOUT_MS, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024,
            stdio: ['ignore', 'pipe', 'ignore'],
        });
    } catch {
        return '';
    }
}
function runAsync(command, args, checked = false) {
    return new Promise((resolve, reject) => execFile(command, args, {
        encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' },
        timeout: COMMAND_TIMEOUT_MS, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024,
    }, (error, stdout) => {
        if (error && checked) return reject(error);
        resolve(error ? '' : stdout);
    }));
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
// Match both comm and argv[0]: a process may rename its comm, and macOS and
// Linux tmux differ in which name pane_current_command reports.
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
function hook(data, agent = 'claude') {
    const { value, keys } = AGENTS[agent];
    const procs = processes();
    let proc = procs.find(p => p.pid === process.ppid);
    const seen = new Set();
    while (proc && !named(proc, agent) && !seen.has(proc.pid)) {
        seen.add(proc.pid);
        proc = procs.find(p => p.pid === proc.parent);
    }
    if (proc && named(proc, agent)) atomic(path.join(cacheDir, `${agent}-${proc.pid}.json`), JSON.stringify({
        start: proc.start,
        data: Object.fromEntries(keys.map(key => [key, data[key]])),
    }));
    const ctx = data.context_window?.used_percentage;
    process.stdout.write(value(data) + (Number.isFinite(ctx) ? ` · ${Math.round(ctx)}% ctx` : ''));
}
async function readPanes(runCommand = runAsync) {
    const rows = await runCommand('tmux', ['list-panes', '-a', '-F', '#{pane_id}\t#{pid}\t#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_active}']);
    return rows.trimEnd().split('\n').map(row => row.split('\t'))
        .filter(row => row.length === 6 && /^%\d+$/.test(row[0]));
}
async function refresh(io = { run: runAsync, processes: async () => processes(await runAsync('ps', ['-axo', PS_FORMAT])), atomic }, snapshot) {
    const panes = (snapshot ?? await readPanes(io.run))
        .filter(([, server, root, agent]) => Object.hasOwn(AGENTS, agent) && /^\d+$/.test(server) && /^\d+$/.test(root));
    // No process scan while idle.
    if (!panes.length) return;
    const procs = await io.processes();
    await Promise.allSettled(panes.map(async pane => {
        const [, server, root, agent] = pane;
        const proc = findAgent(procs, root, agent);
        if (process.argv.includes('--verbose')) process.stdout.write(JSON.stringify({ pane, proc, processCount: procs.length }) + '\n');
        let value = agent;
        if (proc) {
            const cached = readJSON(path.join(cacheDir, `${agent}-${proc.pid}.json`));
            if (cached?.data && cached.start === proc.start) value = AGENTS[agent].value(cached.data);
        }
        (io.atomic || atomic)(path.join(cacheDir, `pane-${server}-${root}`), `${Math.floor(Date.now() / 1000)}\n${agent}\n${value}\n`);
    }));
}
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
        const owner = name.match(/^(?:claude|agy)-(\d+)\.json$/);
        let dead = true;
        if (pane) {
            dead = pane[1] === server ? !livePanes.has(pane[2]) : !alive(Number(pane[1]));
        } else if (owner) {
            dead = !alive(Number(owner[1]));
        }
        if (!dead) continue;
        try { remove(name); removed.push(name); } catch { /* raced another sweep */ }
    }
    return removed;
}
// Agent values remain responsive; Git is cached for 3s and battery for 30s.
// Window emojis and session names are names.sh's, run from tmux hooks.
function createStatusPublisher(runCommand = runAsync, readRecord = (server, pane) => readAgentCache(cacheDir, server, pane), readBattery = battery, sweep = sweepCache) {
    let batteryAt = -Infinity;
    let batteryValue = '';
    let sweptAt = -Infinity;
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
            if (Object.hasOwn(AGENTS, agent) && /^\d+$/.test(server) && /^\d+$/.test(root)) {
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
        set('-g', '@initd-battery', batteryValue ? pill('\u{f0079}', batteryValue, '#{@c-green}') : '');
        // One tmux invocation for the whole tick, as a command sequence. Three
        // panes is 18 option changes, and a process each is the bulk of a
        // publish. Only a standalone ';' argument separates commands, so an
        // embedded one ("feature;wip") passes through untouched; a value that is
        // exactly ';' is escaped, which tmux also rejects when sent on its own.
        if (commands.length) await runCommand('tmux', commands.flatMap((args, index) =>
            (index ? [';'] : []).concat(args.map(arg => arg === ';' ? '\\;' : arg))), true);
        // Commit only after tmux accepts the batch, so a failed write is retried.
        published = nextPublished;
    };
}
async function main() {
    if (process.argv[2] !== 'watch') {
        console.error('Usage: tmux.mjs watch');
        process.exitCode = 1;
        return;
    }
    const publish = createStatusPublisher();
    const socket = run('tmux', ['display-message', '-p', '#{socket_path}']).trim();
    if (!socket) return;
    lockPath = watcherLockPath(socket);
    process.stdout.on('error', () => process.exit(0)); // tmux closed its job pipe
    process.on('exit', () => releaseWatcherLock());
    do {
        if (claimWatcherLock()) {
            const panes = await readPanes();
            try { await refresh(undefined, panes); } catch {}
            try { await publish(undefined, panes); } catch {}
        }
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
    processes, findAgent, atomic, refresh, createStatusPublisher, hook, claimWatcherLock, releaseWatcherLock,
    sweepCache, lockPath, watcherLockPath,
};
let invokedDirectly = false;
try { invokedDirectly = Boolean(process.argv[1]) && fs.realpathSync(process.argv[1]) === filename; } catch {}
if (invokedDirectly) main();
