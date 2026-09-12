#!/usr/bin/env node
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { managedLinks } from './managed-links.mjs';
import { removeLink } from './fs.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const usage = 'Usage: cleanup.mjs <macos|linux> [--dry-run]';
function main(args) {
    if (args.includes('-h') || args.includes('--help')) {
        console.log(usage);
        return;
    }
    const [platform, ...options] = args;
    if (!['macos', 'linux'].includes(platform) || options.some(arg => arg !== '--dry-run')) {
        throw new Error(usage);
    }
    const dryRun = options.includes('--dry-run');
    if (dryRun) console.log(':: Dry run mode — no files will be removed.');
    console.log(`==> Removing initd-managed symlinks from ${process.env.HOME} (${platform})`);
    for (const entry of managedLinks(root, platform, process.env.HOME)) {
        removeLink(entry.home, entry.source, { dryRun });
    }
    console.log('OK Cleanup complete.');
}

try {
    main(process.argv.slice(2));
} catch (error) {
    console.error(`cleanup: ${error.message}`);
    process.exitCode = 1;
}
