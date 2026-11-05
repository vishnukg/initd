// linux/scripts/hyprmoncfg-install.sh: the upstream release rpm replaces the
// stale COPR build. curl is a stub serving files by URL basename, and rpm,
// sudo, dnf and systemctl are stubs that log their arguments, so nothing is
// downloaded or installed. sha256sum is real: the checksum verification is
// the part worth exercising.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../../linux/scripts/hyprmoncfg-install.sh', import.meta.url));
const RPM = 'hyprmoncfg-1.28.0-1.x86_64.rpm';

function fixture({ installed = '1.17.0', copr = true, daemonActive = true, checksum, unreachable = false } = {}) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-hyprmoncfg-'));
    const bin = path.join(root, 'bin');
    const releases = path.join(root, 'releases');
    const log = path.join(root, 'calls.log');
    fs.mkdirSync(bin);
    fs.mkdirSync(releases);
    const rpm = Buffer.from('not really an rpm, but the bytes are what the checksum covers');
    fs.writeFileSync(path.join(releases, RPM), rpm);
    const hash = checksum ?? crypto.createHash('sha256').update(rpm).digest('hex');
    fs.writeFileSync(path.join(releases, 'packaging-checksums.txt'),
        `0000000000000000000000000000000000000000000000000000000000000000  hyprmoncfg_1.28.0_amd64.deb\n${hash}  ${RPM}\n`);
    const stub = (name, body) => fs.writeFileSync(path.join(bin, name), `#!/bin/bash\necho "${name} $*" >> "${log}"\n${body}\n`, { mode: 0o755 });
    // curl -fsSL --max-time N -o <out> <url>: copy the release asset named by the URL.
    stub('curl', unreachable ? 'exit 22' : `out="$5"; name="\${6##*/}"; [ -f "${releases}/$name" ] || exit 22; cp "${releases}/$name" "$out"`);
    stub('rpm', installed ? `printf '%s' "${installed}"` : 'exit 1');
    stub('sudo', 'exit 0');
    stub('dnf', copr ? 'echo copr.fedorainfracloud.org/paolino/hyprmoncfg' : 'exit 0');
    stub('systemctl', `[ "$2" = is-active ] && exit ${daemonActive ? 0 : 3}; exit 0`);
    const run = () => spawnSync('bash', [script], {
        encoding: 'utf8',
        env: { PATH: `${bin}:/usr/bin:/bin`, HYPRMONCFG_RELEASE_BASE: 'https://example.invalid/latest', HYPRMONCFG_ARCH: 'x86_64', HOME: root },
    });
    const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n') : []);
    return { run, calls };
}

test('an older install is upgraded from the verified upstream rpm, the COPR retired and the daemon restarted', () => {
    // Arrange
    const f = fixture({ installed: '1.17.0' });
    // Act
    const result = f.run();
    // Assert
    assert.equal(result.status, 0, result.stderr);
    const calls = f.calls();
    assert.ok(calls.some((c) => /^sudo dnf install -y \S+\/hyprmoncfg-1\.28\.0-1\.x86_64\.rpm$/.test(c)), calls.join('\n'));
    assert.ok(calls.includes('sudo dnf -y copr remove paolino/hyprmoncfg'));
    assert.ok(calls.includes('systemctl --user restart hyprmoncfgd.service'));
    assert.match(result.stdout, /hyprmoncfg 1\.28\.0 installed/);
});

test('the installed version downloads only the checksum file and installs nothing', () => {
    const f = fixture({ installed: '1.28.0', copr: false });
    const result = f.run();
    assert.equal(result.status, 0, result.stderr);
    const calls = f.calls();
    assert.equal(calls.filter((c) => c.startsWith('curl')).length, 1);
    assert.ok(!calls.some((c) => c.includes('dnf install')));
    assert.ok(!calls.some((c) => c.includes('copr remove')));
    assert.match(result.stdout, /already installed/);
});

test('a checksum mismatch fails before dnf sees the file', () => {
    const f = fixture({ checksum: 'deadbeef'.repeat(8) });
    const result = f.run();
    assert.notEqual(result.status, 0);
    assert.ok(!f.calls().some((c) => c.includes('dnf install')), f.calls().join('\n'));
});

test('an unreachable release page is a warning, not a failure, and a missing daemon is not restarted', () => {
    const offline = fixture({ unreachable: true });
    const result = offline.run();
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout + result.stderr, /keeping the installed version/);
    const tty = fixture({ installed: '', daemonActive: false });
    tty.run();
    assert.ok(!tty.calls().includes('systemctl --user restart hyprmoncfgd.service'));
    assert.ok(tty.calls().some((c) => c.includes('dnf install')));
});
