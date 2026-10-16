// The 1Password SSH keys (exe.dev, GitHub) belong to personal machines only, and "personal" here is
// whatever made link.sh link ~/.ssh/config - the script must never write a
// key, or even ~/.ssh, on a machine where that link is absent.
//
// The private keys live in 1Password; the script only copies the public
// halves out of its SSH agent. A stub ssh-add stands in for the agent and answers
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
const GITHUB = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGitHubGitHubGitHubGitHubGitHubGitHubGitH Github';
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
    for (const name of ['ssh-keys.sh', 'logging.sh']) {
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
        githubPub: path.join(home, '.ssh/id_ed25519_github.pub'),
        agentServes: (...lines) => fs.writeFileSync(keys, lines.map(l => `${l}\n`).join('')),
        // What link.sh does on a personal profile.
        linkPersonal: () => {
            fs.mkdirSync(path.join(home, '.ssh'), { recursive: true });
            fs.symlinkSync(managed, path.join(home, '.ssh/config'));
        },
        run: () => spawnSync('bash', [path.join(lib, 'ssh-keys.sh')], {
            cwd: dir, env: { PATH: `${bin}:/usr/bin:/bin`, HOME: home, NO_COLOR: '1' },
            encoding: 'utf8', timeout: 10000,
        }),
    };
}

test('a personal machine gets the exe.dev and GitHub public keys from 1Password, and no other', t => {
    // Arrange: the item is titled "Github"; titles match case-insensitively.
    const f = fixture(t);
    f.linkPersonal();
    f.agentServes(OTHER, GITHUB, EXE);

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(f.pub, 'utf8'), `${EXE}\n`);
    assert.equal(fs.readFileSync(f.githubPub, 'utf8'), `${GITHUB}\n`);
    assert.equal(fs.statSync(f.pub).mode & 0o777, 0o600);
    assert.equal(fs.statSync(f.githubPub).mode & 0o777, 0o600);
    assert.deepEqual(fs.readdirSync(path.join(f.home, '.ssh')).sort(),
        ['config', 'id_ed25519_exe.pub', 'id_ed25519_github.pub']);
});

test('each key is handled on its own: one missing from the agent does not block the other', t => {
    // Arrange
    const f = fixture(t);
    f.linkPersonal();
    f.agentServes(GITHUB);

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(f.githubPub, 'utf8'), `${GITHUB}\n`);
    assert.equal(fs.existsSync(f.pub), false);
    assert.match(result.stderr, /No exe\.dev key/);
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

test('old on-disk private keys are flagged for removal, never deleted', t => {
    // Arrange
    const f = fixture(t);
    f.linkPersonal();
    f.agentServes(EXE, GITHUB);
    const legacy = ['id_ed25519_exe', 'id_ed25519'].map(name => path.join(f.home, '.ssh', name));
    for (const file of legacy) fs.writeFileSync(file, 'old private key', { mode: 0o600 });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    for (const file of legacy) assert.equal(fs.readFileSync(file, 'utf8'), 'old private key');
    assert.match(result.stderr, /old on-disk exe\.dev key/);
    assert.match(result.stderr, /old on-disk GitHub key/);
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
