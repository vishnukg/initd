import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const defaultBrewfile = fileURLToPath(new URL('./Brewfile', import.meta.url));
const usage = `Usage: brewinstall [--formula|--cask] <package>

Add a Homebrew formula or cask to Brewfile, then install it with brew bundle.

  --formula, --brew  Add as a brew formula
  --cask             Add as a cask
  -h, --help         Show this help`;

export function parseArgs(args) {
    let kind;
    let name;
    for (const arg of args) {
        if (arg === '-h' || arg === '--help') return { help: true };
        if (['--formula', '--brew', '--cask'].includes(arg)) {
            const next = arg === '--cask' ? 'cask' : 'brew';
            if (kind && kind !== next) throw new Error('Choose either --formula or --cask');
            kind = next;
        } else if (arg.startsWith('-')) throw new Error(`Unknown option: ${arg}`);
        else if (name !== undefined) throw new Error('Expected exactly one package');
        else name = arg;
    }
    // Permit names, versioned formulae and user/tap/package paths, but no Ruby
    // interpolation, quoting, whitespace, URLs or command-line options.
    if (!name || !/^[a-zA-Z0-9][a-zA-Z0-9+_.@-]*(?:\/[a-zA-Z0-9][a-zA-Z0-9+_.@-]*){0,2}$/.test(name)) {
        throw new Error('A valid Homebrew package name is required');
    }
    return { kind, name };
}

export function appendPackage(file, kind, name) {
    const before = fs.readFileSync(file, 'utf8');
    // Recognize quoted entries with indentation, comments or bundle options.
    const entries = /^\s*(brew|cask)\s+(["'])([^"'\r\n]+)\2\s*(?:,|#|$)/gm;
    if ([...before.matchAll(entries)].some(match => match[1] === kind && match[3] === name)) return false;
    const tmp = path.join(path.dirname(file), `.Brewfile.${randomUUID()}.tmp`);
    try {
        fs.writeFileSync(tmp, before + (before && !before.endsWith('\n') ? '\n' : '') + `${kind} "${name}"\n`, {
            flag: 'wx', mode: fs.statSync(file).mode & 0o777,
        });
        fs.renameSync(tmp, file);
    } finally {
        fs.rmSync(tmp, { force: true });
    }
    return true;
}

export function main(args, { file = defaultBrewfile, run = spawnSync, log = console.log } = {}) {
    const parsed = parseArgs(args);
    if (parsed.help) { log(usage); return; }
    const { name } = parsed;
    let { kind } = parsed;
    fs.accessSync(file, fs.constants.R_OK | fs.constants.W_OK);
    const info = type => {
        const result = run('brew', ['info', type === 'brew' ? '--formula' : '--cask', name], {
            stdio: 'ignore', timeout: 60000, killSignal: 'SIGKILL',
        });
        if (result.error) throw result.error;
        if (result.signal) throw new Error(`brew info terminated by ${result.signal}`);
        return result.status === 0;
    };
    if (kind) {
        if (!info(kind)) throw new Error(`Cannot resolve ${name} as a ${kind === 'brew' ? 'formula' : 'cask'}`);
    } else {
        const formula = info('brew');
        const cask = info('cask');
        if (formula && cask) throw new Error(`${name} exists as both a formula and cask; use --formula or --cask`);
        if (!formula && !cask) throw new Error(`Cannot resolve ${name} as a Homebrew formula or cask`);
        kind = formula ? 'brew' : 'cask';
    }
    log(appendPackage(file, kind, name) ? `Added ${name} to ${file}.` : `${name} is already in ${file}.`);
    // Keep the curated entry if installation fails, so rerunning can retry.
    const result = run('brew', ['bundle', '--file', file], { stdio: 'inherit' });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`brew bundle failed (${result.signal || result.status}); Brewfile entry retained for retry`);
    log('Brewfile applied locally.');
}
