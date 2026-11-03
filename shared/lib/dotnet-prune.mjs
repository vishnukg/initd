#!/usr/bin/env node
// Prune runtime leftovers from mise's shared .NET root.
//
// mise's core:dotnet backend installs every SDK into ONE directory
// (~/.local/share/mise/dotnet-root; installs/dotnet/<version> are symlinks to
// it). `mise uninstall` and `mise upgrade` remove only the sdk/<version>
// directory, never the runtimes, host, reference packs and templates that SDK
// brought with it -- so each patch upgrade left ~100 MB behind, and dropping
// .NET 8 left ~1.7 GB. The update.sh scripts run this after `mise upgrade`.
//
// What is kept: the runtime version each remaining SDK runs on (read from its
// sdk/<version>/dotnet.runtimeconfig.json) and, in every versioned directory,
// the newest version regardless -- so a layout this script misreads costs disk
// space, never a working SDK. Global tools (csharpier, roslyn-language-server)
// roll forward to the newest major, so they need no older runtime.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const usage = 'Usage: dotnet-prune.mjs [--dry-run] [dotnet-root]';
const versionPattern = /^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$/;

function parseVersion(name) {
    const match = versionPattern.exec(name);
    return match && { name, parts: match.slice(1, 4).map(Number), pre: match[4] };
}

function compareVersions(a, b) {
    for (let i = 0; i < 3; i++) if (a.parts[i] !== b.parts[i]) return a.parts[i] - b.parts[i];
    if (!a.pre !== !b.pre) return a.pre ? -1 : 1; // a release outranks its previews
    return (a.pre ?? '').localeCompare(b.pre ?? '', 'en', { numeric: true });
}

function subdirectories(directory) {
    try {
        return fs.readdirSync(directory, { withFileTypes: true })
            .filter(entry => entry.isDirectory()).map(entry => entry.name);
    } catch (error) {
        if (error.code === 'ENOENT') return [];
        throw error;
    }
}

function versionsIn(directory) {
    return subdirectories(directory).map(parseVersion).filter(Boolean);
}

function sdkRuntimeVersion(root, sdk) {
    try {
        const config = JSON.parse(fs.readFileSync(path.join(root, 'sdk', sdk, 'dotnet.runtimeconfig.json'), 'utf8'));
        return config.runtimeOptions?.framework?.version;
    } catch {
        return undefined;
    }
}

function directorySize(target) {
    const stat = fs.lstatSync(target);
    if (!stat.isDirectory()) return stat.size;
    return fs.readdirSync(target).reduce((total, name) => total + directorySize(path.join(target, name)), 0);
}

// Returns the directories it removed (or would remove, with dryRun).
export function pruneDotnetRoot(root, { dryRun = false } = {}) {
    const sdks = versionsIn(path.join(root, 'sdk'));
    const runtimes = new Set(sdks.map(sdk => sdkRuntimeVersion(root, sdk.name)).filter(Boolean));
    // No SDK, or none whose runtime could be read: there is nothing to measure
    // "unused" against, so touch nothing.
    if (sdks.length === 0 || runtimes.size !== sdks.length) return [];

    const runtimeDirectories = [
        ...subdirectories(path.join(root, 'shared')).map(name => path.join(root, 'shared', name)),
        ...subdirectories(path.join(root, 'packs')).map(name => path.join(root, 'packs', name)),
        path.join(root, 'host/fxr'),
        path.join(root, 'templates'),
    ];
    const doomed = [];
    for (const directory of runtimeDirectories) {
        const versions = versionsIn(directory).sort(compareVersions);
        const newest = versions.at(-1);
        for (const version of versions) {
            if (version !== newest && !runtimes.has(version.name)) doomed.push(path.join(directory, version.name));
        }
    }
    // Workload manifests are keyed by SDK feature band (10.0.100); a band whose
    // major.minor no SDK shares belongs to an uninstalled major.
    const majors = new Set(sdks.map(sdk => sdk.parts.slice(0, 2).join('.')));
    for (const band of versionsIn(path.join(root, 'sdk-manifests'))) {
        if (!majors.has(band.parts.slice(0, 2).join('.'))) doomed.push(path.join(root, 'sdk-manifests', band.name));
    }

    const removed = doomed.map(directory => ({ directory, bytes: directorySize(directory) }));
    if (!dryRun) for (const { directory } of removed) fs.rmSync(directory, { recursive: true, force: true });
    return removed;
}

// mise's install path is a symlink into the shared root; resolving it is what
// finds the root without hard-coding mise's data directory.
function miseDotnetRoot() {
    const result = spawnSync('mise', ['where', 'dotnet'], { encoding: 'utf8' });
    if (result.status !== 0 || !result.stdout.trim()) return undefined;
    try { return fs.realpathSync(result.stdout.trim()); } catch { return undefined; }
}

function main(args) {
    if (args.includes('-h') || args.includes('--help')) return console.log(usage);
    const dryRun = args.includes('--dry-run');
    const rest = args.filter(arg => arg !== '--dry-run');
    if (rest.length > 1 || rest.some(arg => arg.startsWith('-'))) throw new Error(usage);
    const root = rest[0] ?? miseDotnetRoot();
    if (!root) return console.log('OK No mise-managed .NET; nothing to prune.');

    const removed = pruneDotnetRoot(root, { dryRun });
    if (removed.length === 0) return console.log('OK .NET root holds only what its SDKs use.');
    const verb = dryRun ? 'Would remove' : 'Removed';
    for (const { directory } of removed) console.log(`    ${verb.toLowerCase()} ${path.relative(root, directory)}`);
    const megabytes = Math.round(removed.reduce((total, entry) => total + entry.bytes, 0) / 1024 / 1024);
    console.log(`OK ${verb} ${removed.length} unused .NET directories (${megabytes} MB).`);
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        main(process.argv.slice(2));
    } catch (error) {
        console.error(`dotnet-prune: ${error.message}`);
        process.exitCode = 1;
    }
}
