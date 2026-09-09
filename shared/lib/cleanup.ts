#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { managedLinks } from './managed-links.ts';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const usage = 'Usage: cleanup.ts <macos|linux> [--dry-run]';
const [platform, ...args] = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
if (!['macos', 'linux'].includes(platform) || args.some(arg => !['--dry-run', '-h', '--help'].includes(arg))) {
    console.error(usage);
    process.exitCode = 1;
} else if (args.includes('-h') || args.includes('--help')) {
    console.log(usage);
} else {
    if (dryRun) console.log(':: Dry run mode — no files will be removed.');
    console.log(`==> Removing initd-managed symlinks from ${process.env.HOME} (${platform})`);
    for (const entry of managedLinks(root, platform, process.env.HOME ?? '')) {
        let stat: fs.Stats;
        try {
            stat = fs.lstatSync(entry.home);
        } catch (error) {
            if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
            console.log(`==> Already absent: ${entry.home}`);
            continue;
        }
        if (!stat.isSymbolicLink()) { console.log(`==> Leaving non-symlink: ${entry.home}`); continue; }
        const target = fs.readlinkSync(entry.home);
        if (target !== entry.source) { console.warn(`!! Leaving symlink outside initd ownership: ${entry.home} -> ${target}`); continue; }
        if (dryRun) console.log(`==> Would remove: ${entry.home} -> ${target}`);
        else { console.log(`==> Removing: ${entry.home}`); fs.unlinkSync(entry.home); }
    }
    console.log('OK Cleanup complete.');
}
