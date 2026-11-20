// vm/scripts/tmux-install.sh: tmux from the tmux project's release builds
// instead of Ubuntu's 3.4. gh is a stub printing the one release row the
// script asks for, and curl a stub serving the archive, so nothing is
// downloaded. tar, sha256sum and install are real: the checksum verification
// and the rename into place are the parts worth exercising. The "tmux" in the
// archive is a shell script that answers -V and display-message.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../../vm/scripts/tmux-install.sh', import.meta.url));
const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-tmux-install-'));
after(() => fs.rmSync(testRoot, { recursive: true, force: true }));

const DAY = 86400;
// A stand-in binary: its version is baked in, the server it reports is read
// from a file beside the test, so one fixture can stage "old server running".
const fakeTmux = (version, serverFile) => [
    '#!/bin/bash',
    `[ "$1" = -V ] && { echo "tmux ${version}"; exit 0; }`,
    `[ "$1" = display-message ] && [ -s "${serverFile}" ] && { cat "${serverFile}"; exit 0; }`,
    'exit 1',
    '',
].join('\n');

function fixture({ installed, latest = '3.8', age = DAY, server = '', arch = 'x86_64', digest, release = true } = {}) {
    const home = fs.mkdtempSync(path.join(testRoot, 'home-'));
    const bin = path.join(home, 'stubs');
    const assets = path.join(home, 'assets');
    const log = path.join(home, 'calls.log');
    const serverFile = path.join(home, 'server-version');
    const dest = path.join(home, '.local/bin/tmux');
    fs.mkdirSync(bin);
    fs.mkdirSync(assets);
    fs.writeFileSync(serverFile, server);
    if (installed) {
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.writeFileSync(dest, fakeTmux(installed, serverFile), { mode: 0o755 });
    }

    const archiveArch = arch === 'aarch64' ? 'arm64' : arch;
    const name = `tmux-${latest}-linux-${archiveArch}.tar.gz`;
    fs.writeFileSync(path.join(assets, 'tmux'), fakeTmux(latest, serverFile), { mode: 0o755 });
    spawnSync('tar', ['-czf', path.join(assets, name), '-C', assets, 'tmux']);
    const hash = crypto.createHash('sha256').update(fs.readFileSync(path.join(assets, name))).digest('hex');
    const row = [`v${latest}`, age, digest ?? `sha256:${hash}`, `https://example.invalid/download/v${latest}/${name}`].join('\t');

    const stub = (command, body) => fs.writeFileSync(path.join(bin, command),
        `#!/bin/bash\necho "${command} $*" >> "${log}"\n${body}\n`, { mode: 0o755 });
    stub('gh', release ? `printf '%s\\n' '${row}'` : 'exit 1');
    // curl -fsSL --max-time N -o <out> <url>: copy the asset named by the URL.
    stub('curl', `out="$5"; name="\${6##*/}"; [ -f "${assets}/$name" ] || exit 22; cp "${assets}/$name" "$out"`);

    return {
        dest,
        run: () => spawnSync('bash', [script], {
            encoding: 'utf8',
            env: { PATH: `${bin}:/usr/bin:/bin:/sbin`, HOME: home, INITD_TMUX_ARCH: arch, NO_COLOR: '1' },
        }),
        // One entry per stub call: the gh query spans lines, so the log is
        // split only where a line starts with a stub's name.
        calls: () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split(/\n(?=(?:gh|curl) )/) : []),
        version: () => spawnSync(dest, ['-V'], { encoding: 'utf8' }).stdout.trim(),
    };
}

test('a box with only apt tmux gets the verified release binary in ~/.local/bin', () => {
    // Arrange
    const f = fixture();

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(f.version(), 'tmux 3.8');
    assert.equal(fs.statSync(f.dest).mode & 0o777, 0o755);
    assert.equal(fs.existsSync(`${f.dest}.new`), false);
    assert.match(result.stdout, /tmux 3\.8 installed/);
});

test('the installed version makes the one API call and downloads nothing', () => {
    // Arrange
    const f = fixture({ installed: '3.8' });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(f.calls().length, 1, f.calls().join('\n'));
    assert.match(f.calls()[0], /^gh api repos\/tmux\/tmux-builds\/releases\/latest /);
    assert.match(result.stdout, /tmux 3\.8 already installed/);
});

test('an older release binary is upgraded in place', () => {
    // Arrange
    const f = fixture({ installed: '3.7c' });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(f.version(), 'tmux 3.8');
});

test('a tampered archive is refused and the installed binary kept', () => {
    // Arrange
    const f = fixture({ installed: '3.7c', digest: `sha256:${'0'.repeat(64)}` });

    // Act
    const result = f.run();

    // Assert
    assert.notEqual(result.status, 0);
    assert.equal(f.version(), 'tmux 3.7c');
});

test('a release without a sha256 digest is not installed', () => {
    // Arrange
    const f = fixture({ digest: 'none' });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(f.dest), false);
    assert.equal(f.calls().some(call => call.startsWith('curl ')), false);
});

test('a release younger than eight hours waits', () => {
    // Arrange
    const f = fixture({ installed: '3.7c', age: 3600 });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(f.version(), 'tmux 3.7c');
    assert.match(result.stdout + result.stderr, /under 8 hours/);
});

test('no gh sign-in or no network is a warning, not a failed update', () => {
    // Arrange
    const f = fixture({ release: false });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(f.dest), false);
    assert.match(result.stdout + result.stderr, /keeping the installed tmux/);
});

test('an aarch64 box asks for the arm64 build', () => {
    // Arrange
    const f = fixture({ arch: 'aarch64' });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.ok(f.calls().some(call => call.startsWith('gh ') && call.includes('linux-arm64.tar.gz')), f.calls().join('\n'));
    assert.equal(f.version(), 'tmux 3.8');
});

test('an architecture with no build is skipped before any network call', () => {
    // Arrange
    const f = fixture({ arch: 'riscv64' });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.calls(), []);
});

test('a server still running the old tmux is called out, since only a restart moves it', () => {
    // Arrange
    const f = fixture({ server: '3.4' });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout + result.stderr, /running tmux server is still 3\.4.*kill-server/);
});

test('a server already on the installed version gets no restart note', () => {
    // Arrange
    const f = fixture({ installed: '3.8', server: '3.8' });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.doesNotMatch(result.stdout + result.stderr, /kill-server/);
});
