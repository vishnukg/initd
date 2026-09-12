import fs from 'node:fs';
import path from 'node:path';

const STATUS_CACHE_TTL_SECONDS = 3;

// Keyed by tmux's #{pane_current_command}, which is an arbitrary string.
// Glyphs stay as \u escapes: they are Private Use Area code points that editors
// and terminals silently drop, which has turned a pill into a bare rectangle
// before now.
const styles = {
    claude: ['#e0af68', '\u{f06a9}'],
    copilot: ['#7aa2f7', '\uf4b8'],
    codex: ['#f7768e', '\uf477'],
};

function clean(value) {
    return String(value).replace(/[\x00-\x1f\x7f#]/g, '').slice(0, 140);
}

function pill(icon, value, color) {
    return `#[fg=#111116,bg=default]\ue0b6#[fg=${color},bg=#111116,bold] ${icon} #[fg=#9aa5ce]${clean(value)} #[fg=#111116,bg=default,nobold]\ue0b4 `;
}

export function agentPill(agent, record = '', now = Date.now() / 1000) {
    if (!Object.hasOwn(styles, agent)) return '';
    const style = styles[agent];
    const [updated, cachedAgent, cached] = record.split('\n');
    let value = cachedAgent === agent && now >= Number(updated)
        && now - Number(updated) < STATUS_CACHE_TTL_SECONDS ? cached || '' : '';
    if (value === agent) value = '';
    for (const prefix of [`${agent}: `, `${agent} · `]) {
        if (value.startsWith(prefix)) value = value.slice(prefix.length);
    }
    const [color, icon] = style;
    return pill(icon, value, color);
}

export async function battery(runCommand, platform = process.platform, directory = '/sys/class/power_supply') {
    if (platform === 'darwin') return (await runCommand('pmset', ['-g', 'batt'])).match(/\b\d{1,3}%/)?.[0] || '';
    try {
        for (const name of fs.readdirSync(directory).filter(name => name.startsWith('BAT'))) {
            const capacity = fs.readFileSync(path.join(directory, name, 'capacity'), 'utf8').trim();
            if (/^\d+$/.test(capacity) && Number(capacity) <= 100) return `${capacity}%`;
        }
    } catch { /* Desktops may have no battery. */ }
    return '';
}

export async function gitPill(directory, runCommand) {
    const branch = (await runCommand('git', ['-C', directory, 'symbolic-ref', '--short', '-q', 'HEAD'])
        || await runCommand('git', ['-C', directory, 'rev-parse', '--short', 'HEAD'])).trim();
    if (!branch) return '';
    const shortened = [...clean(branch)];
    return pill('\u{f062c}', shortened.length > 28 ? shortened.slice(0, 27).join('') + '…' : shortened.join(''), '#bb9af7');
}

export function readAgentCache(cacheDir, server, pane) {
    try { return fs.readFileSync(path.join(cacheDir, `pane-${server}-${pane}`), 'utf8'); }
    catch { return ''; }
}

export { clean, pill };

// Days once past 24h, because a weekly or multi-day reset reads as nonsense in
// hours. codexUsage keeps its own hours-only form: its primary window is 5h.
function remaining(mins) {
    return mins >= 1440 ? `${Math.floor(mins / 1440)}d${Math.floor(mins % 1440 / 60)}h`
        : `${Math.floor(mins / 60)}h${mins % 60}m`;
}
export function codexUsage(limits, now = Date.now() / 1000) {
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
// Usage-limit errors sometimes carry a reset date only in their message.
// Keep the limit notice even if the date is absent, unparseable, or past.
export function codexLimit(message, now = Date.now() / 1000) {
    if (!message) return '';
    const at = message.match(/try again at ([A-Za-z]{3,}\s+\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4}),?\s+(\d{1,2}:\d{2}\s*[AP]M)/i);
    const reset = at ? Date.parse(`${at[1]}, ${at[2]} ${at[3]}`) / 1000 : NaN;
    if (!Number.isFinite(reset) || reset <= now) return ' · limit';
    return ` · limit · ${remaining(Math.ceil((reset - now) / 60))}`;
}
// Copilot's model-call events carry the session's own quota snapshot.
export function copilotUsage(data, now = Date.now() / 1000) {
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
            value += ` · ${remaining(Math.ceil((reset - now) / 60))}`;
        }
        return value;
    }
    return '';
}
// Prefer the five-hour window. A week or budget can take its place once it
// reaches 50% and is fuller; with no five-hour data, use an available window.
const ESCALATE_AT_PERCENT = 50;
export function claudeValue(data, now = Date.now() / 1000) {
    const model = clean(data.model?.display_name || 'claude');
    const windows = [['spend_limit', ' budget'], ['five_hour', ''], ['seven_day', ' week']]
        .map(([key, label]) => ({ key, label, limit: data.rate_limits?.[key] }))
        .filter(({ limit }) => Number.isFinite(limit?.used_percentage) && limit.used_percentage >= 0
            && Number.isFinite(limit.resets_at) && limit.resets_at > now);
    // The threshold is a floor on escalation rather than a priority: a slower
    // window has to clear it AND be the fuller one to take the slot, so a 5h
    // window about to stop the next turn is never hidden behind a week that
    // merely looks busy.
    const chosen = windows
        .filter(({ key, limit }) => key === 'five_hour' || limit.used_percentage >= ESCALATE_AT_PERCENT)
        .sort((a, b) => b.limit.used_percentage - a.limit.used_percentage)[0]
        // Nothing qualified, so there is no 5h window here to hold the slot; a
        // quiet slower one still beats showing a bare model name.
        || windows[0];
    if (!chosen) return model;
    const left = remaining(Math.ceil((chosen.limit.resets_at - now) / 60));
    return `${model} · ${Math.round(chosen.limit.used_percentage)}%${chosen.label} · ${left}`;
}
