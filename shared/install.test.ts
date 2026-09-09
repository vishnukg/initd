// Behavior tests for the Bash install helpers. Node owns isolation, assertions
// and reporting; the scripts under test remain the production implementation.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { managedLinks } from './lib/managed-links.ts';
import { configureProfile } from './lib/git-profile.ts';
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const root = path.resolve(__dirname, '..');
function hostPlatform(): 'macos' | 'linux' {
    if (process.platform === 'darwin') return 'macos';
    if (process.platform === 'linux') return 'linux';
    throw new Error(`Unsupported platform: ${process.platform}`);
}
const platform = hostPlatform();
const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-install-'));
after(() => fs.rmSync(testRoot, { recursive: true, force: true }));

function run(command: string, args: string[], options: { env?: NodeJS.ProcessEnv } = {}): string {
    const result = spawnSync(command, args, { ...options, encoding: 'utf8' });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`${command} exited ${result.status}: ${result.stderr}`);
    return result.stdout + result.stderr;
}
function newHome(name: string): string {
    return fs.mkdtempSync(path.join(testRoot, `${name}-`));
}
function links() {
    return testLinks(path.join(testRoot, 'inspect-home'));
}
function testLinks(home: string) {
    return managedLinks(root, platform, home);
}
function link(home: string, backupRoot: string): string {
    return run(path.join(root, 'shared/lib/link.sh'), [platform], {
        env: { ...process.env, HOME: home, BACKUP_ROOT: backupRoot },
    });
}
function cleanup(home: string): string {
    return run(process.execPath, [path.join(root, 'shared/lib/cleanup.ts'), platform], { env: { ...process.env, HOME: home } });
}
function assertLink(file: string, expected: string): void {
    assert.equal(fs.readlinkSync(file), expected, `${file} should point at ${expected}`);
}

test('clean install creates every managed symlink', () => {
    const home = newHome('clean');
    const output = link(home, path.join(home, '.config/initd-backups'));
    assert.match(output, /Managed symlinks verified\./);
    for (const entry of testLinks(home)) assertLink(entry.home, entry.source);
});

test('managed links stay within the current platform and shared roots', () => {
    const allowed = [path.join(root, 'shared') + path.sep, path.join(root, platform) + path.sep];
    const forbidden = path.join(root, platform === 'macos' ? 'linux' : 'macos') + path.sep;
    for (const entry of links()) {
        assert.equal(entry.source.startsWith(forbidden), false, `cross-platform link: ${entry.source}`);
        assert.ok(allowed.some(prefix => entry.source.startsWith(prefix)), `out-of-scope link: ${entry.source}`);
    }
});

test('install backs up unmanaged configs before linking', () => {
    const home = newHome('backup');
    const backupRoot = path.join(home, '.config/initd-backups');
    const files = [
        ['.config/mise/config.toml', 'user mise config'],
        ['.config/nvim/init.lua', 'user nvim config'],
        ['.config/fish/config.fish', 'user fish config'],
        ['.config/ghostty/config', 'user ghostty config'],
        ['.config/kitty/kitty.conf', 'user kitty config'],
        ['.gitconfig', 'user git config'],
    ];
    for (const [relative, value] of files) {
        const file = path.join(home, relative);
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, value);
    }
    const output = link(home, backupRoot);
    assert.match(output, /Backing up unmanaged/);
    for (const entry of testLinks(home)) assertLink(entry.home, entry.source);
    for (const [relative, value] of files) {
        assert.equal(fs.readFileSync(path.join(backupRoot, relative), 'utf8'), value);
    }
});

test('personal Git profile does not write an override', () => {
    const output = run(process.execPath, [path.join(root, 'shared/lib/git-profile.ts'), 'personal']);
    assert.match(output, /using the default git email/);
});

test('a broken managed symlink is backed up and repaired', () => {
    const home = newHome('broken');
    const backupRoot = path.join(home, '.config/initd-backups');
    fs.symlinkSync(path.join(root, 'shared/configs/git/missing.gitconfig'), path.join(home, '.gitconfig'));
    link(home, backupRoot);
    const gitconfig = path.join(root, 'shared/configs/git/gitconfig');
    assertLink(path.join(home, '.gitconfig'), gitconfig);
    const backups = fs.readdirSync(backupRoot, { recursive: true, encoding: 'utf8' }).filter(file => path.basename(file) === '.gitconfig');
    assert.equal(backups.length, 1);
    assert.ok(fs.lstatSync(path.join(backupRoot, backups[0]!)).isSymbolicLink());
});

test('cleanup removes only owned managed links', () => {
    const home = newHome('cleanup');
    for (const entry of testLinks(home)) {
        fs.mkdirSync(path.dirname(entry.home), { recursive: true });
        fs.symlinkSync(entry.source, entry.home);
    }
    fs.mkdirSync(path.join(home, 'outside'));
    fs.symlinkSync(path.join(home, 'outside/keep'), path.join(home, '.unrelated'));
    fs.writeFileSync(path.join(home, 'real-file'), 'real file');
    const output = cleanup(home);
    assert.match(output, /Cleanup complete\./);
    for (const entry of testLinks(home)) assert.throws(() => fs.lstatSync(entry.home), { code: 'ENOENT' });
    assert.ok(fs.lstatSync(path.join(home, '.unrelated')).isSymbolicLink());
    assert.equal(fs.readFileSync(path.join(home, 'real-file'), 'utf8'), 'real file');
});

test('manifest paths are literal, including shell syntax and newlines', () => {
    const unusual = path.join(newHome('literal'), 'repo $(printf changed) `printf changed`\n');
    fs.symlinkSync(root, unusual);
    const home = path.join(testRoot, 'home $(printf changed)\n');
    for (const entry of managedLinks(unusual, platform, home)) {
        assert.ok(entry.home.startsWith(home + '/'));
        assert.ok(entry.source.startsWith(unusual + '/'));
    }
});

test('interactive profile selection preserves unrelated config and quotes email', async () => {
    const override = path.join(newHome('profile'), 'local.gitconfig');
    fs.writeFileSync(override, '[other]\n email = unrelated\n[core]\n editor = nvim\n');
    const answers = ['work', 'someone#work@example.com'];
    await configureProfile([], { override, interactive: true, ask: async () => answers.shift() ?? '', log() {} });
    assert.equal(answers.length, 0);
    assert.equal(run('git', ['config', '--file', override, 'user.email']).trim(), 'someone#work@example.com');
    assert.equal(run('git', ['config', '--file', override, 'core.editor']).trim(), 'nvim');
    assert.deepEqual(fs.readdirSync(path.dirname(override)), ['local.gitconfig']);
    await configureProfile(['work'], { override, interactive: true, ask() { throw new Error('Should not prompt'); }, log() {} });
});

test('personal, noninteractive and help profiles do not create an override', async () => {
    const override = path.join(newHome('no-profile'), 'local.gitconfig');
    for (const args of [['personal'], [], ['work'], ['--help']]) {
        await configureProfile(args, { override, interactive: false, log() {} });
        assert.throws(() => fs.lstatSync(override), { code: 'ENOENT' });
    }
});

test('cleanup dry run preserves links and unmanaged replacements stay untouched', () => {
    const home = newHome('cleanup-safe');
    const entries = testLinks(home);
    for (const entry of entries) {
        fs.mkdirSync(path.dirname(entry.home), { recursive: true });
        fs.symlinkSync(entry.source, entry.home);
    }
    run(process.execPath, [path.join(root, 'shared/lib/cleanup.ts'), platform, '--dry-run'], { env: { ...process.env, HOME: home } });
    for (const entry of entries) assertLink(entry.home, entry.source);
    fs.unlinkSync(entries[0].home);
    fs.symlinkSync('/missing/user-owned', entries[0].home);
    fs.unlinkSync(entries[1].home);
    fs.writeFileSync(entries[1].home, 'keep');
    cleanup(home);
    assertLink(entries[0].home, '/missing/user-owned');
    assert.equal(fs.readFileSync(entries[1].home, 'utf8'), 'keep');
});

test('cleanup reports filesystem errors instead of claiming paths are absent', () => {
    const home = newHome('cleanup-error');
    fs.symlinkSync(path.join(home, '.config'), path.join(home, '.config'));
    assert.throws(() => cleanup(home), /ELOOP/);
});
