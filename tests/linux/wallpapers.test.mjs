// Wallpapers are optional: an offline machine must still bootstrap, so every
// path through linux/scripts/wallpapers.sh warns and exits 0.
//
// The script derives ROOT_DIR from its own BASH_SOURCE, so linking the real
// script into a scratch tree runs the production file against a disposable
// root, and HOME points the clone target into the same scratch tree.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));
const sshUrl = 'git@github.com:vishnukg/wallpapers.git';
const url = 'https://github.com/vishnukg/wallpapers.git';

function fixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-wallpapers-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const scripts = path.join(dir, 'repo/linux/scripts');
    const lib = path.join(dir, 'repo/shared/lib');
    const bin = path.join(dir, 'bin');
    fs.mkdirSync(scripts, { recursive: true });
    fs.mkdirSync(lib, { recursive: true });
    fs.mkdirSync(bin);
    fs.symlinkSync(path.join(root, 'linux/scripts/wallpapers.sh'), path.join(scripts, 'wallpapers.sh'));
    fs.symlinkSync(path.join(root, 'shared/lib/logging.sh'), path.join(lib, 'logging.sh'));
    const calls = path.join(dir, 'calls');
    return {
        dir,
        wallpapers: path.join(dir, '.local/share/wallpapers'),
        calls: () => (fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8').trim().split('\n') : []),
        git: body => fs.writeFileSync(path.join(bin, 'git'),
            `#!/bin/sh\necho "git $*" >> ${calls}\n${body}\n`, { mode: 0o755 }),
        run: () => spawnSync('bash', [path.join(scripts, 'wallpapers.sh')], {
            cwd: dir, env: { PATH: `${bin}:/usr/bin:/bin`, HOME: dir, NO_COLOR: '1' },
            encoding: 'utf8', timeout: 10000,
        }),
    };
}

test('a fresh machine clones the wallpapers repo over SSH into the XDG data dir', t => {
    // Arrange
    const f = fixture(t);
    f.git('[ "$1" = clone ] && mkdir -p "$6/.git"\nexit 0');

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Wallpapers cloned/);
    assert.deepEqual(f.calls(), [`git clone --depth 1 --quiet ${sshUrl} ${f.wallpapers}`]);
    assert.equal(fs.existsSync(path.join(f.wallpapers, '.git')), true);
});

test('the SSH clone never prompts: ssh runs in batch mode', t => {
    // Arrange
    const f = fixture(t);
    f.git('echo "ssh: $GIT_SSH_COMMAND" >> "$(dirname "$0")/../calls"\n[ "$1" = clone ] && mkdir -p "$6/.git"\nexit 0');

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(f.calls().join('\n'), /ssh: ssh -o BatchMode=yes/);
});

test('a clone SSH cannot authenticate falls back to HTTPS', t => {
    // Arrange
    const f = fixture(t);
    f.git(`case "$*" in *${sshUrl}*) exit 128 ;; esac\n[ "$1" = clone ] && mkdir -p "$6/.git"\nexit 0`);

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /falling back to HTTPS/);
    assert.match(result.stdout, /Wallpapers cloned/);
    assert.deepEqual(f.calls(), [
        `git clone --depth 1 --quiet ${sshUrl} ${f.wallpapers}`,
        `git clone --depth 1 --quiet ${url} ${f.wallpapers}`,
    ]);
    assert.equal(fs.existsSync(path.join(f.wallpapers, '.git')), true);
});

test('a clone that fails over both SSH and HTTPS warns without failing the bootstrap', t => {
    // Arrange
    const f = fixture(t);
    f.git('exit 128');

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0);
    assert.match(result.stderr, /Could not clone/);
    assert.equal(fs.existsSync(f.wallpapers), false);
});

test('the old initd wallpaper link is replaced by a clone', t => {
    // Arrange
    const f = fixture(t);
    fs.mkdirSync(path.dirname(f.wallpapers), { recursive: true });
    fs.symlinkSync(path.join(f.dir, 'repo/shared/wallpaper'), f.wallpapers);
    f.git('[ "$1" = clone ] && mkdir -p "$6/.git"\nexit 0');

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.lstatSync(f.wallpapers).isSymbolicLink(), false);
    assert.equal(fs.existsSync(path.join(f.wallpapers, '.git')), true);
});

test('an existing clone is pulled, and an offline pull keeps what is there', t => {
    // Arrange
    const f = fixture(t);
    fs.mkdirSync(path.join(f.wallpapers, '.git'), { recursive: true });
    fs.writeFileSync(path.join(f.wallpapers, 'wall.jpg'), 'pixels');
    f.git('exit 0');

    // Act
    const updated = f.run();

    // Assert
    assert.equal(updated.status, 0, updated.stderr);
    assert.match(updated.stdout, /Wallpapers up to date/);
    assert.deepEqual(f.calls(), [`git -C ${f.wallpapers} pull --ff-only --quiet`]);

    // Arrange
    f.git('exit 1');

    // Act
    const offline = f.run();

    // Assert
    assert.equal(offline.status, 0);
    assert.match(offline.stderr, /keeping existing wallpapers/);
    assert.equal(fs.readFileSync(path.join(f.wallpapers, 'wall.jpg'), 'utf8'), 'pixels');
});

test('a directory or link this script does not own is left alone', t => {
    // Arrange
    const f = fixture(t);
    const mine = path.join(f.dir, 'my-pictures');
    fs.mkdirSync(mine);
    fs.mkdirSync(path.dirname(f.wallpapers), { recursive: true });
    fs.symlinkSync(mine, f.wallpapers);
    f.git('exit 0');

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0);
    assert.match(result.stderr, /not a git clone/);
    assert.deepEqual(f.calls(), [], 'git must not touch a path this script does not own');
    assert.equal(fs.readlinkSync(f.wallpapers), mine);
});
