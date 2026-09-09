import fs from 'node:fs';
import path from 'node:path';

/** Spawns a command and resolves its stdout, resolving '' rather than throwing. */
export type RunCommand = (command: string, args: string[]) => Promise<string>;

export const STATUS_CACHE_TTL_SECONDS = 3;

// Keyed by tmux's #{pane_current_command}, which is an arbitrary string.
const styles: Record<string, [color: string, icon: string]> = {
    claude: ['#e0af68', '\u{f06a9}'],
    copilot: ['#7aa2f7', '\uf4b8'],
    codex: ['#f7768e', '\uf477'],
};

function clean(value: unknown): string {
    return String(value).replace(/[\x00-\x1f\x7f#]/g, '').slice(0, 140);
}

function pill(icon: string, value: string, color: string): string {
    return `#[fg=#111116,bg=default]\ue0b6#[fg=${color},bg=#111116,bold] ${icon} #[fg=#9aa5ce]${clean(value)} #[fg=#111116,bg=default,nobold]\ue0b4 `;
}

export function agentPill(agent: string, record = '', now = Date.now() / 1000): string {
    const style = styles[agent];
    if (!style) return '';
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

export async function battery(
    runCommand: RunCommand,
    platform: NodeJS.Platform = process.platform,
    directory = '/sys/class/power_supply',
): Promise<string> {
    if (platform === 'darwin') return (await runCommand('pmset', ['-g', 'batt'])).match(/\b\d{1,3}%/)?.[0] || '';
    try {
        for (const name of fs.readdirSync(directory).filter(name => name.startsWith('BAT'))) {
            const capacity = fs.readFileSync(path.join(directory, name, 'capacity'), 'utf8').trim();
            if (/^\d+$/.test(capacity) && Number(capacity) <= 100) return `${capacity}%`;
        }
    } catch { /* Desktops may have no battery. */ }
    return '';
}

export async function gitPill(directory: string, runCommand: RunCommand): Promise<string> {
    const branch = (await runCommand('git', ['-C', directory, 'symbolic-ref', '--short', '-q', 'HEAD'])
        || await runCommand('git', ['-C', directory, 'rev-parse', '--short', 'HEAD'])).trim();
    if (!branch) return '';
    const shortened = [...clean(branch)];
    return pill('\u{f062c}', shortened.length > 28 ? shortened.slice(0, 27).join('') + '…' : shortened.join(''), '#bb9af7');
}

export function readAgentCache(cacheDir: string, server: string, pane: string): string {
    try { return fs.readFileSync(path.join(cacheDir, `pane-${server}-${pane}`), 'utf8'); }
    catch { return ''; }
}

export { clean, pill };
