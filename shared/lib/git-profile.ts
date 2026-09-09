#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline/promises';
import { spawnSync, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const filename = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(filename), '../..');
const usage = 'Usage: git-profile.ts [personal|work]';

export interface ProfileOptions {
    override?: string;
    interactive?: boolean;
    /** Injected in tests so the prompt does not need a real TTY. */
    ask?: (text: string) => Promise<string>;
    log?: (message: string) => void;
}

export async function configureProfile(args: string[], {
    override = path.join(root, 'shared/configs/git/local.gitconfig'),
    interactive = process.stdin.isTTY,
    ask,
    log = console.log,
}: ProfileOptions = {}): Promise<void> {
    if (args.length === 1 && ['--help', '-h'].includes(args[0]!)) return log(usage);
    if (args.length > 1 || (args[0] && !['personal', 'work'].includes(args[0]))) throw new Error(usage);
    let prompt: readline.Interface | undefined;
    const question = ask || ((text: string) => {
        prompt ||= readline.createInterface({ input: process.stdin, output: process.stdout });
        return prompt.question(text);
    });
    try {
        const profile = args[0] || (interactive
            ? (await question(':: Machine type [personal/work] (default: personal): ')).trim() || 'personal'
            : 'personal');
        if (!['personal', 'work'].includes(profile)) throw new Error(usage);
        if (profile === 'personal') return log('OK Personal machine — using the default git email; no override needed.');

        const existing = spawnSync('git', ['config', '--file', override, '--get', 'user.email'], { encoding: 'utf8' });
        if (existing.error) throw existing.error;
        if (existing.status === null || ![0, 1].includes(existing.status)) throw new Error('Cannot read Git identity configuration');
        if (existing.stdout.trim()) return log(`OK Work git email already set: ${existing.stdout.trim()}`);
        if (!interactive) return log('!! No work git email set — run shared/lib/git-profile.ts work interactively to configure it.');
        const email = (await question(':: Work git email for this machine: ')).trim();
        if (!email) return log('!! No email entered — work identity unchanged.');

        fs.mkdirSync(path.dirname(override), { recursive: true });
        const temporary = fs.mkdtempSync(path.join(path.dirname(override), '.git-profile-'));
        try {
            const file = path.join(temporary, 'config');
            try { fs.copyFileSync(override, file); }
            catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
            // Git handles quoting and preserves other machine-local settings.
            execFileSync('git', ['config', '--file', file, 'user.email', email]);
            fs.chmodSync(file, 0o600);
            fs.renameSync(file, override);
        } finally {
            fs.rmSync(temporary, { recursive: true, force: true });
        }
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
