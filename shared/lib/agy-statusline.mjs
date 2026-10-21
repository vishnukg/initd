#!/usr/bin/env node
// Points the Antigravity CLI's statusLine at shared/configs/tmux's
// agy-statusline-hook.mjs, which feeds the agy pill in the tmux status line
// the same way claude-statusline.mjs does for Claude. Run standalone or from a
// platform bootstrap, AFTER link.sh so the hook's path already resolves
// through the ~/.config/tmux symlink.
//
// Not a MANAGED_LINKS symlink for the same reason as Claude's: agy writes its
// own settings (model, theme, permissions) into this file, so only the
// statusLine key is merged in place.
//
// The command is an absolute path, not ~/...: agy rewrites a ~ path to an
// absolute one itself, which would read as a change on every bootstrap.
// `enabled` is written for the same reason - agy adds it when it saves.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sameFlatObject, updateJsonFile } from './json-file.mjs';

export function configureAgyStatusLine({
    home = process.env.HOME,
    file = path.join(home, '.gemini/antigravity-cli/settings.json'),
    log = console.log,
} = {}) {
    const statusLine = {
        type: 'command',
        command: path.join(home, '.config/tmux/agy-statusline-hook.mjs'),
        enabled: true,
    };
    const changed = updateJsonFile(file, config => {
        if (sameFlatObject(config.statusLine, statusLine)) return false;
        config.statusLine = statusLine;
        return true;
    });
    log(`OK Antigravity CLI statusLine ${changed ? 'configured' : 'already configured'} (${file}).`);
    return changed;
}

const filename = fileURLToPath(import.meta.url);
if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        configureAgyStatusLine();
    } catch (error) {
        console.error(`ERR Failed to update Antigravity CLI settings: ${error.message}`);
        process.exitCode = 1;
    }
}
