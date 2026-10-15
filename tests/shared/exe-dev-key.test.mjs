// The exe.dev key belongs to personal machines only, and "personal" here is
// whatever made link.sh link ~/.ssh/config - the script must never create a
// key, or even ~/.ssh, on a machine where that link is absent.
//
// As in fonts.test.mjs, the script derives ROOT_DIR from its own BASH_SOURCE,
// so linking the real script into a scratch tree runs the production file
// against a disposable root. ssh-keygen is the real one.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));

function fixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-exe-key-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const lib = path.join(dir, 'repo/shared/lib');
    const home = path.join(dir, 'home');
    fs.mkdirSync(lib, { recursive: true });
    fs.mkdirSync(home);
    for (const name of ['exe-dev-key.sh', 'logging.sh']) {
        fs.symlinkSync(path.join(root, 'shared/lib', name), path.join(lib, name));
    }
    const managed = path.join(dir, 'repo/shared/configs/ssh/.ssh/config');
    fs.mkdirSync(path.dirname(managed), { recursive: true });
    fs.writeFileSync(managed, 'Host dev\n');
    return {
        home,
        key: path.join(home, '.ssh/id_ed25519_exe'),
        // What link.sh does on a personal profile.
        linkPersonal: () => {
            fs.mkdirSync(path.join(home, '.ssh'), { recursive: true });
            fs.symlinkSync(managed, path.join(home, '.ssh/config'));
        },
        run: () => spawnSync('bash', [path.join(lib, 'exe-dev-key.sh')], {
            cwd: dir, env: { PATH: '/usr/bin:/bin', HOME: home, NO_COLOR: '1' },
            encoding: 'utf8', timeout: 10000,
        }),
    };
}

test('a personal machine gets an exe.dev key and the registration steps', t => {
    // Arrange
    const f = fixture(t);
    f.linkPersonal();

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.statSync(f.key).mode & 0o777, 0o600);
    const pub = fs.readFileSync(`${f.key}.pub`, 'utf8').trim();
    assert.match(pub, /^ssh-ed25519 \S+ \S+ exe\.dev$/);
    assert.ok(result.stdout.includes(pub), 'the public key is printed for pasting');
    assert.match(result.stdout, /SAME email/);
});

test('an existing key is kept as it is', t => {
    // Arrange
    const f = fixture(t);
    f.linkPersonal();
    fs.writeFileSync(f.key, 'existing', { mode: 0o600 });

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(f.key, 'utf8'), 'existing');
    assert.match(result.stdout, /exe\.dev key present/);
});

test('a work machine gets no key, no ~/.ssh and no output', t => {
    // Arrange: no managed link - neither a missing ~/.ssh/config nor the
    // machine's own file may count as personal.
    const f = fixture(t);
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
