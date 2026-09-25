#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline/promises';
import { spawnSync, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const filename = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(filename), '../..');
const usage = 'Usage: git-profile.mjs [personal|work]';
// The shared gitconfig carries no email: every machine, personal included, gets
// its identity from local.gitconfig, and user.useConfigOnly refuses to commit
// without one.
const personalEmail = 'vishnukg@gmail.com';

function writeOverride(override, args) {
    fs.mkdirSync(path.dirname(override), { recursive: true });
    const temporary = fs.mkdtempSync(path.join(path.dirname(override), '.git-profile-'));
    try {
        const file = path.join(temporary, 'config');
        try { fs.copyFileSync(override, file); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        execFileSync('git', ['config', '--file', file, ...args]);
        fs.chmodSync(file, 0o600);
        fs.renameSync(file, override);
    } finally {
        fs.rmSync(temporary, { recursive: true, force: true });
    }
}

// `ask` is injected in tests so the prompt does not need a real TTY.
export async function configureProfile(args, {
    override = path.join(root, 'shared/configs/git/local.gitconfig'),
    interactive = process.stdin.isTTY,
    ask,
    log = console.log,
} = {}) {
    if (args.length === 1 && ['--help', '-h'].includes(args[0])) return log(usage);
    if (args.length > 1 || (args[0] && !['personal', 'work'].includes(args[0]))) throw new Error(usage);
    let prompt;
    const question = ask || (text => {
        prompt ||= readline.createInterface({ input: process.stdin, output: process.stdout });
        return prompt.question(text);
    });
    try {
        const existing = spawnSync('git', ['config', '--file', override, '--get', 'user.email'], { encoding: 'utf8' });
        if (existing.error) throw existing.error;
        if (![0, 1].includes(existing.status)) throw new Error('Cannot read Git identity configuration');
        const current = existing.stdout.trim();

        // No default profile: pressing Enter on a work machine must not quietly
        // commit as the personal identity.
        const profile = args[0] || (interactive
            ? (await question(':: Machine type [personal/work]: ')).trim()
            : '');
        if (!profile) {
            return log(current
                ? 'OK Existing Git identity unchanged.'
                : '!! No Git email set — run shared/lib/git-profile.mjs personal or work to configure it.');
        }
        if (!['personal', 'work'].includes(profile)) throw new Error(usage);

        if (profile === 'personal') {
            if (current === personalEmail) return log(`OK Personal git email already set: ${current}`);
            writeOverride(override, ['user.email', personalEmail]);
            return log(`OK Personal git email set to: ${personalEmail}`);
        }
        if (current && current !== personalEmail) return log(`OK Work git email already set: ${current}`);
        if (!interactive) return log('!! No work git email set — run shared/lib/git-profile.mjs work interactively to configure it.');
        const email = (await question(':: Work git email for this machine: ')).trim();
        if (!email) return log('!! No email entered — work identity unchanged.');

        // Git handles quoting and preserves other machine-local settings.
        writeOverride(override, ['user.email', email]);
        log(`OK Work git email set to: ${email}`);
    } finally {
        prompt?.close();
    }
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    configureProfile(process.argv.slice(2)).catch(error => {
        console.error(error.message);
        process.exitCode = 1;
    });
}
