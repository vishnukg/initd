// Bind status to the pane's process and its open transcript, never log recency.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const cacheDir = path.join(process.env.HOME, '.cache/initd-tmux');
const transcriptCache = new Map();
const sourceVersion = fs.statSync(__filename).mtimeMs;
function run(command, args) {
    // ps lstart follows locale (e.g. "Sep 8" vs "8 Sep"); fix its wire format.
    try { return execFileSync(command, args, { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' }, timeout: 3000, maxBuffer: 8 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] }); }
    catch { return ''; }
}
function readJSON(file) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}
function atomic(file, value) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.${process.pid}.${require('node:crypto').randomUUID()}.tmp`;
    try { fs.writeFileSync(tmp, value, { mode: 0o600 }); fs.renameSync(tmp, file); }
    finally { try { fs.unlinkSync(tmp); } catch {} }
}
function processes() {
    return run('ps', ['-axo', 'pid=,ppid=,lstart=,comm=']).trim().split('\n').flatMap(line => {
        const m = line.trim().match(/^(\d+)\s+(\d+)\s+(\S+\s+\S+\s+\d+\s+\S+\s+\d+)\s+(.+)$/);
        return m ? [{ pid: Number(m[1]), parent: Number(m[2]), start: m[3], agent: path.basename(m[4]) }] : [];
    });
}
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
async function copilotSessionFile(output, pid) {
    // Copilot closes events.jsonl between writes, but keeps its own process log
    // open. Resolve only that PID's log and its latest foreground registration.
    const files = [...new Set(output.split('\n').filter(l => l.startsWith('n')).map(l => l.slice(1))
        .filter(file => path.basename(path.dirname(file)) === 'logs'
            && new RegExp(`^process-\\d+-${Number(pid)}\\.log$`).test(path.basename(file))))];
    if (files.length !== 1) return null;
    try {
        const state = await sessionState('copilot-process', files[0]);
        return state.sessionId ? path.join(path.dirname(files[0]), '..', 'session-state', state.sessionId, 'events.jsonl') : null;
    } catch { return null; }
}
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
                    const match = line.toString('utf8').match(/^\S+ \[INFO\] (Registering|Unregistering) foreground session: ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s*$/i);
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
function clean(value) { return String(value).replace(/[\x00-\x1f\x7f#]/g, '').slice(0, 140); }
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
function claudeValue(data) {
    const model = clean(data.model?.display_name || 'claude');
    const five = data.rate_limits?.five_hour;
    if (!five || !Number.isFinite(five.used_percentage) || !Number.isFinite(five.resets_at)) return model;
    return model + codexUsage({ primary: { used_percent: five.used_percentage, resets_at: five.resets_at } });
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
async function refresh(io = { run, processes }) {
    const panes = io.run('tmux', ['list-panes', '-a', '-F', '#{pid}|#{pane_pid}|#{pane_current_command}']).trim().split('\n')
        .filter(pane => /\|(claude|codex|copilot)$/.test(pane));
    // No process scans, open-file queries or transcript reads while idle.
    if (!panes.length) return;
    const procs = io.processes();
    for (const pane of panes) {
        const [server, root, agent] = pane.split('|');
        if (!/^\d+$/.test(server) || !/^\d+$/.test(root)) continue;
        if (!['claude', 'codex', 'copilot'].includes(agent)) continue;
        const proc = findAgent(procs, root, agent);
        if (process.argv.includes('--verbose')) process.stdout.write(JSON.stringify({ pane, proc, processCount: procs.length }) + '\n');
        let value = agent;
        if (proc) {
            if (agent === 'claude') {
                const cached = readJSON(path.join(cacheDir, `claude-${proc.pid}.json`));
                if (cached?.start === proc.start) value = claudeValue(cached.data);
            } else {
                const openFiles = io.run('lsof', ['-a', '-p', String(proc.pid), '-Fn']);
                const file = sessionFile(agent, openFiles)
                    || (agent === 'copilot' ? await copilotSessionFile(openFiles, proc.pid) : null);
                if (process.argv.includes('--verbose')) process.stdout.write(JSON.stringify({ agent, file }) + '\n');
                if (file) {
                    try {
                        const state = await sessionState(agent, file);
                        value = state.model ? clean(state.model) : agent;
                        if (agent === 'codex') value += codexUsage(state.rateLimits);
                    } catch { /* The session may exit while its log is read. */ }
                }
            }
        }
        atomic(path.join(cacheDir, `pane-${server}-${root}`), `${Math.floor(Date.now() / 1000)}\n${agent}\n${value}\n`);
    }
}
async function main() {
    if (process.argv[2] === 'hook') {
        try { hook(JSON.parse(fs.readFileSync(0, 'utf8'))); } catch {}
        return;
    }
    do {
        try { await refresh(); } catch {}
        if (process.argv[2] === 'once') return;
        process.stdout.write('\n');
        await new Promise(resolve => setTimeout(resolve, 3000));
        // tmux restarts the same #() job on its next redraw. Source changes take
        // effect without changing the job key or leaving old worker versions alive.
        if (fs.statSync(__filename).mtimeMs !== sourceVersion) return;
    } while (true);
}
module.exports = { findAgent, sessionFile, copilotSessionFile, modelEvent, sessionState, claudeValue, codexUsage, atomic, refresh };
if (require.main === module) main();
