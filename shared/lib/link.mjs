#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { managedLinks } from './managed-links.mjs';
import { defaultBackupRoot, installLink } from './fs.mjs';

const filename = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(filename), '../..');

export function installManagedLinks(platform, {
    home = process.env.HOME, backupRoot = defaultBackupRoot(home), log = console.log,
} = {}) {
    const links = managedLinks(root, platform, home);
    log(`:: Backups for unmanaged configs will go under ${backupRoot}`);
    for (const entry of links) installLink(entry.home, entry.source, { home, backupRoot, log });
    log('OK Managed symlinks verified.');
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        const args = process.argv.slice(2);
        if (args.length !== 1 || !['macos', 'linux'].includes(args[0])) {
            throw new Error('Usage: link.mjs <macos|linux>');
        }
        installManagedLinks(args[0]);
    } catch (error) {
        console.error(`link: ${error.message}`);
        process.exitCode = 1;
    }
}
