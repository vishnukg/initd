import fs from 'node:fs';
import path from 'node:path';

const STATUS_CACHE_TTL_SECONDS = 3;

// Keyed by tmux's #{pane_current_command}, which is an arbitrary string.
// Glyphs stay as \u escapes: they are Private Use Area code points that editors
// and terminals silently drop, which has turned a pill into a bare rectangle
// before now.
// Colours are tmux.conf's @c-* palette, referenced rather than copied: the pills
// are expanded by status-right (#{E:...}), so #{@c-amber} becomes the hex there.
// clean() strips '#' from every value, so no branch or model name can inject a
// format into that expansion.
const styles = {
    claude: ['#{@c-amber}', '\u{f06a9}'],
    agy: ['#{@c-blue}', '\ue90c'],
};

function clean(value) {
    return String(value).replace(/[\x00-\x1f\x7f#]/g, '').slice(0, 140);
}

// status-right expands the pills (#{E:...}) so the palette references resolve,
// and that expansion also runs strftime: a bare '%' is consumed ("89%" renders
// "89"), so it is doubled here - not in clean(), which also feeds Claude's own
// status line.
function pill(icon, value, color) {
    return `#[fg=#{@c-pill},bg=default]\ue0b6#[fg=${color},bg=#{@c-pill},bold] ${icon} #[fg=#{@c-text}]${clean(value).replaceAll('%', '%%')} #[fg=#{@c-pill},bg=default,nobold]\ue0b4 `;
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
    return pill('\u{f062c}', shortened.length > 28 ? shortened.slice(0, 27).join('') + '…' : shortened.join(''), '#{@c-purple}');
}

export function readAgentCache(cacheDir, server, pane) {
    try { return fs.readFileSync(path.join(cacheDir, `pane-${server}-${pane}`), 'utf8'); }
    catch { return ''; }
}

export { clean, pill };

// Days once past 24h, because a weekly or multi-day reset reads as nonsense in
// hours.
function remaining(mins) {
    return mins >= 1440 ? `${Math.floor(mins / 1440)}d${Math.floor(mins % 1440 / 60)}h`
        : `${Math.floor(mins / 60)}h${mins % 60}m`;
}
// Prefer the five-hour window. A week or budget can take its place once it
// reaches 50% and is fuller; with no five-hour data, use an available window.
const ESCALATE_AT_PERCENT = 50;
// windows: [{ label, fiveHour, used, resetsAt }], used in percent and resetsAt
// in epoch seconds. Expired or malformed windows are dropped here.
function withQuota(model, windows, now) {
    const live = windows.filter(({ used, resetsAt }) => Number.isFinite(used) && used >= 0
        && Number.isFinite(resetsAt) && resetsAt > now);
    // The threshold is a floor on escalation rather than a priority: a slower
    // window has to clear it AND be the fuller one to take the slot, so a 5h
    // window about to stop the next turn is never hidden behind a week that
    // merely looks busy.
    const chosen = live
        .filter(({ fiveHour, used }) => fiveHour || used >= ESCALATE_AT_PERCENT)
        .sort((a, b) => b.used - a.used)[0]
        // Nothing qualified, so there is no 5h window here to hold the slot; a
        // quiet slower one still beats showing a bare model name.
        || live[0];
    if (!chosen) return model;
    const left = remaining(Math.ceil((chosen.resetsAt - now) / 60));
    return `${model} · ${Math.round(chosen.used)}%${chosen.label} · ${left}`;
}
export function claudeValue(data, now = Date.now() / 1000) {
    const model = clean(data.model?.display_name || 'claude');
    return withQuota(model, [['spend_limit', ' budget'], ['five_hour', ''], ['seven_day', ' week']]
        .map(([key, label]) => {
            const limit = data.rate_limits?.[key];
            return { label, fiveHour: key === 'five_hour', used: limit?.used_percentage, resetsAt: limit?.resets_at };
        }), now);
}
// Antigravity reports quota as a map of remaining fractions, one family per
// model provider: gemini-* for Gemini models, 3p-* for third-party ones. The
// absolute reset_time is used rather than reset_in_seconds, which is relative
// to when the payload was written and goes stale in the cache.
export function agyValue(data, now = Date.now() / 1000) {
    const model = clean(data.model?.display_name || 'agy');
    const family = /gemini/i.test(data.model?.id || data.model?.display_name || '') ? 'gemini' : '3p';
    return withQuota(model, [['5h', ''], ['weekly', ' week']].map(([window, label]) => {
        const quota = data.quota?.[`${family}-${window}`];
        const fraction = quota?.remaining_fraction;
        return {
            label, fiveHour: window === '5h',
            used: Number.isFinite(fraction) && fraction <= 1 ? (1 - fraction) * 100 : NaN,
            resetsAt: Date.parse(quota?.reset_time) / 1000,
        };
    }), now);
}
