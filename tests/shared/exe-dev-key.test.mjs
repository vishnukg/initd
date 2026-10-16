// The exe.dev key belongs to personal machines only, and "personal" here is
// whatever made link.sh link ~/.ssh/config - the script must never write a
// key, or even ~/.ssh, on a machine where that link is absent.
//
// The private key lives in 1Password; the script only copies the public half
// out of its SSH agent. A stub ssh-add stands in for the agent and answers
// only on the socket path the managed SSH config names.
//
// As in fonts.test.mjs, the script derives ROOT_DIR from its own BASH_SOURCE,
// so linking the real script into a scratch tree runs the production file
// against a disposable root.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));

const EXE = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExeDevExeDevExeDevExeDevExeDevExeDevExeDev exe.dev';
const OTHER = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherOtherOtherOtherOtherOtherOtherOther Other';

function fixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-exe-key-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const lib = path.join(dir, 'repo/shared/lib');
    const home = path.join(dir, 'home');
    const bin = path.join(dir, 'bin');
    fs.mkdirSync(lib, { recursive: true });
    fs.mkdirSync(home);
    fs.mkdirSync(bin);
    for (const name of ['exe-dev-key.sh', 'logging.sh']) {
        fs.symlinkSync(path.join(root, 'shared/lib', name), path.join(lib, name));
    }
    const managed = path.join(dir, 'repo/shared/configs/ssh/.ssh/config');
    fs.mkdirSync(path.dirname(managed), { recursive: true });
    fs.writeFileSync(managed, 'Host dev\n');
    const keys = path.join(dir, 'agent-keys');
    // Like the real ssh-add -L: exit 1 when the agent holds nothing.
    fs.writeFileSync(path.join(bin, 'ssh-add'), `#!/bin/sh
[ "$1" = -L ] && [ "$SSH_AUTH_SOCK" = "${home}/.1password/agent.sock" ] && [ -s "${keys}" ] || exit 1
cat "${keys}"
`, { mode: 0o755 });
    return {
        home,
        pub: path.join(home, '.ssh/id_ed25519_exe.pub'),
        agentServes: (...lines) => fs.writeFileSync(keys, lines.map(l => `${l}\n`).join('')),
        // What link.sh does on a personal profile.
        linkPersonal: () => {
            fs.mkdirSync(path.join(home, '.ssh'), { recursive: true });
            fs.symlinkSync(managed, path.join(home, '.ssh/config'));
        },
        run: () => spawnSync('bash', [path.join(lib, 'exe-dev-key.sh')], {
            cwd: dir, env: { PATH: `${bin}:/usr/bin:/bin`, HOME: home, NO_COLOR: '1' },
            encoding: 'utf8', timeout: 10000,
        }),
    };
}

test('a personal machine gets the exe.dev public key from 1Password, and no other', t => {
    // Arrange
    const f = fixture(t);
    f.linkPersonal();
    f.agentServes(OTHER, EXE);

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(f.pub, 'utf8'), `${EXE}\n`);
    assert.equal(fs.statSync(f.pub).mode & 0o777, 0o600);
    assert.deepEqual(fs.readdirSync(path.join(f.home, '.ssh')).sort(), ['config', 'id_ed25519_exe.pub']);
});

test('a rotated key replaces the old public half, which is tightened to 0600', t => {
    // Arrange
    const f = fixture(t);
    f.linkPersonal();
    fs.writeFileSync(f.pub, `${OTHER}\n`, { mode: 0o644 });
    f.agentServes(EXE);

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(f.pub, 'utf8'), `${EXE}\n`);
    assert.equal(fs.statSync(f.pub).mode & 0o777, 0o600);
});

test('a locked or absent agent keeps an existing public key and only warns', t => {
    // Arrange
    const f = fixture(t);
    f.linkPersonal();
    fs.writeFileSync(f.pub, `${EXE}\n`, { mode: 0o600 });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(f.pub, 'utf8'), `${EXE}\n`);
    assert.match(result.stderr, /not serving 'exe\.dev'; keeping/);
});

test('with no agent and no public key, bootstrap continues with the setup steps', t => {
    // Arrange
    const f = fixture(t);
    f.linkPersonal();

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(f.pub), false);
    assert.match(result.stderr, /No exe\.dev key/);
    assert.match(result.stdout, /Use the SSH agent/);
});

test('an old on-disk private key is flagged for removal, never deleted', t => {
    // Arrange
    const f = fixture(t);
    f.linkPersonal();
    f.agentServes(EXE);
    const legacy = path.join(f.home, '.ssh/id_ed25519_exe');
    fs.writeFileSync(legacy, 'old private key', { mode: 0o600 });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(legacy, 'utf8'), 'old private key');
    assert.match(result.stderr, /old on-disk exe\.dev key/);
});

test('a work machine gets no key, no ~/.ssh and no output', t => {
    // Arrange: no managed link - neither a missing ~/.ssh/config nor the
    // machine's own file may count as personal, even with the agent serving.
    const f = fixture(t);
    f.agentServes(EXE);
    const bare = f.run();
    fs.mkdirSync(path.join(f.home, '.ssh'));
    fs.writeFileSync(path.join(f.home, '.ssh/config'), 'Host work\n');

    // Act
    const own = f.run();

    // Assert
    assert.equal(bare.status, 0, bare.stderr);
    assert.equal(bare.stdout + bare.stderr, '');
    assert.equal(own.status, 0, own.stderr);
    assert.equal(own.stdout + own.stderr, '');
    assert.deepEqual(fs.readdirSync(path.join(f.home, '.ssh')), ['config']);
});
