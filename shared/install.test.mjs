// Behavior tests for the Bash install helpers. Node owns isolation, assertions
// and reporting; the scripts under test remain the production implementation.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { managedLinks } from './lib/managed-links.mjs';
import { configureProfile } from './lib/git-profile.mjs';
import { backupPath, installLink } from './lib/fs.mjs';
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const root = path.resolve(__dirname, '..');
const platform = process.platform === 'darwin' ? 'macos' : process.platform === 'linux' ? 'linux' : null;
if (!platform) throw new Error(`Unsupported platform: ${process.platform}`);
const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-install-'));
after(() => fs.rmSync(testRoot, { recursive: true, force: true }));

function run(command, args, options = {}) {
    const result = spawnSync(command, args, { encoding: 'utf8', ...options });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`${command} exited ${result.status}: ${result.stderr}`);
    return result.stdout + result.stderr;
}
function newHome(name) {
    return fs.mkdtempSync(path.join(testRoot, `${name}-`));
}
function links() {
    return testLinks(path.join(testRoot, 'inspect-home'));
}
function testLinks(home) {
    return managedLinks(root, platform, home);
}
function link(home, backupRoot) {
    return run(process.execPath, [path.join(root, 'shared/lib/link.mjs'), platform], {
        env: { ...process.env, HOME: home, BACKUP_ROOT: backupRoot },
    });
}
function cleanup(home) {
    return run(process.execPath, [path.join(root, 'shared/lib/cleanup.mjs'), platform], { env: { ...process.env, HOME: home } });
}
function assertLink(file, expected) {
    assert.equal(fs.readlinkSync(file), expected, `${file} should point at ${expected}`);
}

test('clean install creates every managed symlink', () => {
    // Arrange
    const home = newHome('clean');

    // Act
    const output = link(home, path.join(home, '.config/initd-backups'));

    // Assert
    assert.match(output, /Managed symlinks verified\./);

    for (const entry of testLinks(home)) {
        assertLink(entry.home, entry.source);
    }
});

test('managed links stay within the current platform and shared roots', () => {
    // Arrange
    const allowed = [path.join(root, 'shared') + path.sep, path.join(root, platform) + path.sep];
    const forbidden = path.join(root, platform === 'macos' ? 'linux' : 'macos') + path.sep;

    // Act
    const entries = links();

    // Assert
    for (const entry of entries) {
        assert.equal(entry.source.startsWith(forbidden), false, `cross-platform link: ${entry.source}`);
        assert.ok(allowed.some(prefix => entry.source.startsWith(prefix)), `out-of-scope link: ${entry.source}`);
    }
});

test('install backs up unmanaged configs before linking', () => {
    // Arrange
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

    // Act
    const output = link(home, backupRoot);

    // Assert
    assert.match(output, /Backing up unmanaged/);

    for (const entry of testLinks(home)) {
        assertLink(entry.home, entry.source);
    }

    for (const [relative, value] of files) {
        assert.equal(fs.readFileSync(path.join(backupRoot, relative), 'utf8'), value);
    }
});

test('personal Git profile does not write an absent override', async () => {
    // Arrange
    const override = path.join(newHome('personal'), 'local.gitconfig');
    const output = [];

    // Act
    await configureProfile(['personal'], { override, log: line => output.push(line) });

    // Assert
    assert.match(output.join('\n'), /using the default git email/);
    assert.equal(fs.existsSync(override), false);
});

test('reusing a backup directory preserves older files, directories and broken symlinks', () => {
    // Arrange
    const home = newHome('backup-collision');
    const backups = path.join(home, 'backups');
    fs.mkdirSync(backups);
    fs.writeFileSync(path.join(backups, 'settings'), 'first');
    fs.mkdirSync(path.join(backups, 'settings.1'));
    fs.writeFileSync(path.join(backups, 'settings.1', 'kept'), 'directory');
    fs.symlinkSync('missing', path.join(backups, 'settings.2'));
    fs.writeFileSync(path.join(home, 'settings'), 'latest');

    // Act
    backupPath(path.join(home, 'settings'), { home, backupRoot: backups, log() {} });

    // Assert
    assert.equal(fs.readFileSync(path.join(backups, 'settings'), 'utf8'), 'first');
    assert.equal(fs.readFileSync(path.join(backups, 'settings.1', 'kept'), 'utf8'), 'directory');
    assert.equal(fs.readlinkSync(path.join(backups, 'settings.2')), 'missing');
    assert.equal(fs.readFileSync(path.join(backups, 'settings.3'), 'utf8'), 'latest');
    assert.equal(fs.existsSync(path.join(home, 'settings')), false);
});

test('a broken managed symlink is backed up and repaired', () => {
    // Arrange
    const home = newHome('broken');
    const backupRoot = path.join(home, '.config/initd-backups');
    fs.symlinkSync(path.join(root, 'shared/configs/git/missing.gitconfig'), path.join(home, '.gitconfig'));

    // Act
    link(home, backupRoot);

    // Arrange
    const gitconfig = path.join(root, 'shared/configs/git/gitconfig');

    // Assert
    assertLink(path.join(home, '.gitconfig'), gitconfig);
    const backups = fs.readdirSync(backupRoot, { recursive: true }).filter(file => path.basename(file) === '.gitconfig');
    assert.equal(backups.length, 1);
    assert.ok(fs.lstatSync(path.join(backupRoot, backups[0])).isSymbolicLink());
});

test('cleanup removes only owned managed links', () => {
    // Arrange
    const home = newHome('cleanup');

    // Act
    for (const entry of testLinks(home)) {
        fs.mkdirSync(path.dirname(entry.home), { recursive: true });
        fs.symlinkSync(entry.source, entry.home);
    }

    // Arrange
    fs.mkdirSync(path.join(home, 'outside'));
    fs.symlinkSync(path.join(home, 'outside/keep'), path.join(home, '.unrelated'));
    fs.writeFileSync(path.join(home, 'real-file'), 'real file');

    // Act
    const output = cleanup(home);

    // Assert
    assert.match(output, /Cleanup complete\./);

    for (const entry of testLinks(home)) {
        assert.throws(() => fs.lstatSync(entry.home), { code: 'ENOENT' });
    }

    assert.ok(fs.lstatSync(path.join(home, '.unrelated')).isSymbolicLink());
    assert.equal(fs.readFileSync(path.join(home, 'real-file'), 'utf8'), 'real file');
});

test('manifest paths are literal, including shell syntax and newlines', () => {
    // Arrange
    const unusual = path.join(newHome('literal'), 'repo $(printf changed) `printf changed`\n');
    fs.symlinkSync(root, unusual);
    const home = path.join(testRoot, 'home $(printf changed)\n');

    // Act
    const entries = managedLinks(unusual, platform, home);

    // Assert
    for (const entry of entries) {
        assert.ok(entry.home.startsWith(home + '/'));
        assert.ok(entry.source.startsWith(unusual + '/'));
    }
});

test('interactive profile selection preserves unrelated config and quotes email', async () => {
    // Arrange
    const override = path.join(newHome('profile'), 'local.gitconfig');
    fs.writeFileSync(override, '[other]\n email = unrelated\n[core]\n editor = nvim\n');
    const answers = ['work', 'someone#work@example.com'];
    let repeatPrompts = 0;

    // Act
    await configureProfile([], { override, interactive: true, ask: async () => answers.shift(), log() {} });
    const email = run('git', ['config', '--file', override, 'user.email']).trim();
    const editor = run('git', ['config', '--file', override, 'core.editor']).trim();
    await configureProfile(['work'], { override, interactive: true, ask() { repeatPrompts++; throw new Error('Should not prompt'); }, log() {} });

    // Assert
    assert.equal(answers.length, 0);
    assert.equal(email, 'someone#work@example.com');
    assert.equal(editor, 'nvim');
    assert.deepEqual(fs.readdirSync(path.dirname(override)), ['local.gitconfig']);
    assert.equal(repeatPrompts, 0);
});

for (const args of [['personal'], [], ['work'], ['--help']]) {
    test(`noninteractive Git profile ${args.join(' ') || '(default)'} does not create an override`, async () => {
        // Arrange
        const override = path.join(newHome('no-profile'), 'local.gitconfig');

        // Act
        await configureProfile(args, { override, interactive: false, log() {} });

        // Assert
        assert.throws(() => fs.lstatSync(override), { code: 'ENOENT' });
    });
}

test('switching back to personal removes only the email override', async () => {
    // Arrange
    const override = path.join(newHome('switch-profile'), 'local.gitconfig');
    fs.writeFileSync(override, '[user]\nemail = work@example.com\n[core]\neditor = nvim\n');

    // Act
    await configureProfile([], { override, interactive: false, log() {} });
    const runResult = run('git', ['config', '--file', override, 'user.email']).trim();

    // Assert
    assert.equal(runResult, 'work@example.com');

    // Act
    await configureProfile(['personal'], { override, interactive: false, log() {} });
    const spawnSyncResult = spawnSync('git', ['config', '--file', override, '--get', 'user.email']).status;

    // Assert
    assert.equal(spawnSyncResult, 1);

    // Act
    const runResult2 = run('git', ['config', '--file', override, 'core.editor']).trim();

    // Assert
    assert.equal(runResult2, 'nvim');
});

test('Linux manifest installs and cleans up in an isolated home on either host', () => {
    // Arrange
    const home = newHome('linux-links');
    const env = { ...process.env, HOME: home };
    const entries = managedLinks(root, 'linux', home);

    // Act
    run(process.execPath, [path.join(root, 'shared/lib/link.mjs'), 'linux'], { env });
    const installed = entries.map(entry => ({
        target: fs.readlinkSync(entry.home), exists: fs.existsSync(entry.home),
    }));
    run(process.execPath, [path.join(root, 'shared/lib/cleanup.mjs'), 'linux'], { env });

    // Assert
    for (const [index, entry] of entries.entries()) {
        assert.equal(installed[index].target, entry.source);
        assert.equal(installed[index].exists, true, `broken source: ${entry.source}`);
        assert.equal(fs.existsSync(entry.home), false);
    }
});

test('cleanup dry run preserves links and unmanaged replacements stay untouched', () => {
    // Arrange
    const home = newHome('cleanup-safe');

    const entries = testLinks(home);
    for (const entry of entries) {
        fs.mkdirSync(path.dirname(entry.home), { recursive: true });
        fs.symlinkSync(entry.source, entry.home);
    }

    // Act
    run(process.execPath, [path.join(root, 'shared/lib/cleanup.mjs'), platform, '--dry-run'], { env: { ...process.env, HOME: home } });

    // Assert
    for (const entry of entries) {
        assertLink(entry.home, entry.source);
    }

    // Arrange: replace two owned links with user files before cleanup.
    fs.unlinkSync(entries[0].home);
    fs.symlinkSync('/missing/user-owned', entries[0].home);
    fs.unlinkSync(entries[1].home);
    fs.writeFileSync(entries[1].home, 'keep');

    // Act
    cleanup(home);

    // Assert
    assertLink(entries[0].home, '/missing/user-owned');
    assert.equal(fs.readFileSync(entries[1].home, 'utf8'), 'keep');
});

test('cleanup reports filesystem errors instead of claiming paths are absent', () => {
    // Arrange
    const home = newHome('cleanup-error');
    fs.symlinkSync(path.join(home, '.config'), path.join(home, '.config'));

    // Act: define the operation whose error behavior is checked below
    const act = () => cleanup(home);

    // Assert
    assert.throws(act, /ELOOP/);
});

test('link launcher requests Node explicitly before any managed mise config exists', () => {
    // Arrange
    const home = newHome('fresh-launcher');
    const bin = path.join(home, 'bin');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'mise'), [
        '#!/bin/sh',
        '[ "$1" = -C ] && [ "$2" = "$INITD_ROOT" ] && [ "$3" = exec ] || exit 90',
        '[ "$4" = node@lts ] && [ "$5" = -- ] && [ "$6" = node ] || exit 91',
        '[ ! -e "$HOME/.config/mise/config.toml" ] || exit 92',
        'shift 6',
        'exec "$INITD_NODE" "$@"',
        '',
    ].join('\n'), { mode: 0o755 });

    // Act
    run(path.join(root, 'shared/lib/link.sh'), [platform], {
        env: { ...process.env, HOME: home, PATH: `${bin}:/usr/bin:/bin`, INITD_ROOT: root, INITD_NODE: process.execPath },
    });
    // Assert
    for (const entry of testLinks(home)) {
        assertLink(entry.home, entry.source);
    }
});

test('a missing link source never moves an unmanaged destination', () => {
    // Arrange
    const home = newHome('missing-source');
    const file = path.join(home, 'config');
    fs.writeFileSync(file, 'keep');

    // Act: define the operation whose error behavior is checked below
    const act = () => installLink(file, path.join(home, 'missing'), { home, backupRoot: path.join(home, 'backup') });

    // Assert
    assert.throws(act, /source path/);
    assert.equal(fs.readFileSync(file, 'utf8'), 'keep');
    assert.equal(fs.existsSync(path.join(home, 'backup')), false);
});

test('backups outside HOME stay beneath backupRoot', () => {
    // Arrange
    const home = newHome('outside-home');
    const source = path.join(newHome('checkout'), 'config');
    fs.writeFileSync(source, 'keep');
    const backupRoot = path.join(home, 'backup');

    // Act
    const backup = backupPath(source, { home, backupRoot, log() {} });

    // Assert
    assert.ok(backup.startsWith(backupRoot + path.sep));
    assert.equal(fs.readFileSync(backup, 'utf8'), 'keep');
});
