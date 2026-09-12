#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { backupPath, defaultBackupRoot, installLink, pointsTo } from '../../shared/lib/fs.mjs';

const filename = fileURLToPath(import.meta.url);
const repo = path.resolve(path.dirname(filename), '../..');

export function configureLinks({
    root = repo, home = process.env.HOME, backupRoot = defaultBackupRoot(home), log = console.log,
} = {}) {
    const options = { home, backupRoot, log };
    const scripts = path.join(root, 'linux/scripts');
    const configs = path.join(root, 'linux/configs');
    const oldAudio = path.join(home, '.config/audio-ports.sh');
    if (pointsTo(oldAudio, path.join(scripts, 'audio-ports.sh'))) backupPath(oldAudio, options);

    const links = [
        [path.join(root, 'shared/configs/ghostty/.config/ghostty/linux.conf'), path.join(configs, 'ghostty/linux.conf')],
        [path.join(home, '.gtkrc-2.0'), path.join(configs, 'gtkrc-2.0')],
        [path.join(home, '.icons/default/index.theme'), path.join(configs, 'icons-default/index.theme')],
    ];
    for (const name of ['night-light-toggle.mjs', 'weather-popup.mjs', 'docker-menu.mjs', 'audio-ports.mjs']) {
        links.push([path.join(home, '.config', name), path.join(scripts, name)]);
    }
    for (const [file, source] of links) installLink(file, source, options);
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        if (process.argv.length !== 2) throw new Error('Usage: config-links.mjs');
        configureLinks();
    } catch (error) {
        console.error(`config-links: ${error.message}`);
        process.exitCode = 1;
    }
}
