#!/usr/bin/env node
// Print / Super+Shift+S. `full` captures every output; `region` lets slurp pick
// an area, saves it, and copies the PNG to the clipboard as well.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const usage = 'Usage: screenshot.mjs [full|region]';

// stdin is either a file descriptor (wl-copy reads the PNG from it) or ignored.
// stdout/stderr are never piped to wl-copy: it forks a daemon that keeps
// serving the clipboard, and that child would hold a pipe open until timeout.
function run(command, args, { stdin = 'ignore', capture = false } = {}) {
    const result = spawnSync(command, args, {
        stdio: [stdin, capture ? 'pipe' : 'ignore', capture ? 'pipe' : 'ignore'],
        encoding: 'utf8', timeout: 60000, killSignal: 'SIGKILL',
    });
    if (result.error) throw result.error;
    return { status: result.status, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
}

function notify(message) {
    run('notify-send', ['-t', '3000', 'Screenshot', message]);
}

const pad = n => String(n).padStart(2, '0');
export function screenshotPath(home, now) {
    const stamp = [now.getFullYear(), pad(now.getMonth() + 1), pad(now.getDate()),
        pad(now.getHours()), pad(now.getMinutes()), pad(now.getSeconds())].join('-');
    return path.join(home, 'Pictures', 'Screenshots', `screenshot-${stamp}.png`);
}

export function screenshot(mode, {
    home = process.env.HOME, now = new Date(), io = { run, notify },
} = {}) {
    if (mode !== 'full' && mode !== 'region') throw new Error(usage);
    const file = screenshotPath(home, now);
    try {
        fs.mkdirSync(path.dirname(file), { recursive: true });
        const grim = [file];
        if (mode === 'region') {
            const slurp = io.run('slurp', [], { capture: true });
            // Escape or a click outside any output: the user cancelled, not a failure.
            if (slurp.status !== 0) return null;
            grim.unshift('-g', slurp.stdout.trim());
        }
        const shot = io.run('grim', grim, { capture: true });
        if (shot.status !== 0) throw new Error(shot.stderr.trim() || `grim exited ${shot.status}`);
        if (mode === 'region') {
            const fd = fs.openSync(file, 'r');
            try {
                const copy = io.run('wl-copy', ['--type', 'image/png'], { stdin: fd });
                if (copy.status !== 0) throw new Error(`wl-copy exited ${copy.status}`);
            } finally {
                fs.closeSync(fd);
            }
        }
        return file;
    } catch (error) {
        // The bind has no terminal, so stderr alone would go nowhere visible.
        const message = `Failed: ${error.message}`;
        try { io.notify(message); } catch { console.error(message); }
        return false;
    }
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        if (process.argv.length > 3) throw new Error(usage);
        if (screenshot(process.argv[2] ?? 'full') === false) process.exitCode = 1;
    } catch (error) {
        console.error(`screenshot: ${error.message}`);
        process.exitCode = 1;
    }
}
