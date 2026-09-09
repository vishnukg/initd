import { execFileSync } from 'node:child_process';

// Returns { home, source } per link: the path in $HOME and its target in the repo.
export function managedLinks(root, platform, home) {
    if (!['macos', 'linux'].includes(platform)) throw new Error(`Unsupported platform: ${platform}`);
    const script = [
        'set -euo pipefail',
        'ROOT_DIR=$1',
        'source "$ROOT_DIR/shared/managed-links.sh"',
        'source "$ROOT_DIR/$2/managed-links.sh"',
        "printf '%s\\0' \"${MANAGED_LINKS[@]}\"",
    ].join('\n');
    // Paths are data, never shell source. NUL framing preserves whitespace.
    return execFileSync('bash', ['-c', script, 'managed-links', root, platform], {
        encoding: 'utf8', env: { ...process.env, HOME: home },
    }).split('\0').filter(Boolean).map(entry => {
        const separator = entry.indexOf(':', home.length);
        if (separator < 0 || !entry.startsWith(home + '/')) throw new Error('Invalid managed link');
        return { home: entry.slice(0, separator), source: entry.slice(separator + 1) };
    });
}
