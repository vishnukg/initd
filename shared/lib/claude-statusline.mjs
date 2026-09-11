#!/usr/bin/env node
// Points Claude Code's statusLine hook at shared/configs/tmux's
// claude-statusline-hook.mjs, which is what feeds the Claude pill in the tmux
// status line with server-authoritative rate-limit data (see that script's
// header for why). Run standalone or from a platform bootstrap, AFTER link.sh so
// the hook's path already resolves through the ~/.config/tmux symlink.
//
// Not a MANAGED_LINKS symlink: ~/.claude/settings.json also holds
// user/machine-specific Claude Code settings (modelSettings, theme, ...) this
// repo has no business overwriting, so one key is merged in place instead. Lives
// in shared/ rather than per-platform because ~/.claude sits at the same path
// under $HOME on macOS and Linux and nothing here is platform-specific.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sameFlatObject, updateJsonFile } from './json-file.mjs';

const STATUS_LINE = {
    type: 'command',
    command: '~/.config/tmux/claude-statusline-hook.mjs',
    refreshInterval: 60,
};

export function configureStatusLine({
    file = path.join(process.env.HOME, '.claude/settings.json'),
    log = console.log,
} = {}) {
    const changed = updateJsonFile(file, config => {
        if (sameFlatObject(config.statusLine, STATUS_LINE)) return false;
        config.statusLine = STATUS_LINE;
        return true;
    });
    log(`OK Claude Code statusLine hook ${changed ? 'configured' : 'already configured'} (${file}).`);
    return changed;
}

const filename = fileURLToPath(import.meta.url);
if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        configureStatusLine();
    } catch (error) {
        console.error(`ERR Failed to update Claude Code settings: ${error.message}`);
        process.exitCode = 1;
    }
}
