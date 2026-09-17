// Fonts are optional and licensed: the private repo may be unreachable on any
// given machine, so every path through this script must warn and still exit 0,
// or a fresh bootstrap stops before it has linked anything.
//
// The script derives ROOT_DIR from its own BASH_SOURCE, and a symlink reports
// the link's directory rather than the target's - so linking the real script
// into a scratch tree runs the production file against a disposable root.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));

function fixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-fonts-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const lib = path.join(dir, 'repo/shared/lib');
    const bin = path.join(dir, 'bin');
    fs.mkdirSync(lib, { recursive: true });
    fs.mkdirSync(bin);
    for (const name of ['fonts.sh', 'logging.sh']) {
        fs.symlinkSync(path.join(root, 'shared/lib', name), path.join(lib, name));
    }
    const calls = path.join(dir, 'calls');
    return {
        fonts: path.join(dir, 'repo/shared/fonts'),
        calls: () => (fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8').trim().split('\n') : []),
        // Each fake records its invocation, so "never consulted" is assertable.
        tool: (name, body) => fs.writeFileSync(path.join(bin, name),
            `#!/bin/sh\necho "${name} $*" >> ${calls}\n${body}\n`, { mode: 0o755 }),
        // cwd is the scratch tree: a fake that mishandles a relative path must
        // not be able to create anything inside the checkout.
        run: () => spawnSync('bash', [path.join(lib, 'fonts.sh')], {
            cwd: dir, env: { PATH: `${bin}:/usr/bin:/bin`, HOME: dir, NO_COLOR: '1' },
            encoding: 'utf8', timeout: 10000,
        }),
    };
}

test('an unauthenticated machine skips the font sync and still succeeds', t => {
    // Arrange
    const f = fixture(t);
    f.tool('gh', 'exit 1');

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, 'bootstrap must continue without licensed fonts');
    assert.match(result.stderr, /gh is not authenticated/);
    assert.match(result.stdout, /gh auth login/);
    assert.equal(fs.existsSync(f.fonts), false);
    assert.deepEqual(f.calls(), ['gh auth status']);
});

test('a missing gh is indistinguishable from an unauthenticated one', t => {
    // Arrange
    const f = fixture(t);

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0);
    assert.match(result.stderr, /gh is not authenticated/);
    assert.deepEqual(f.calls(), [], 'nothing is run when gh is absent');
});

test('an authenticated machine clones the private repo into the gitignored directory', t => {
    // Arrange
    const f = fixture(t);
    f.tool('gh', `[ "$1" = repo ] && mkdir -p "$4"\nexit 0`);

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Fonts cloned/);
    assert.deepEqual(f.calls(), ['gh auth status', `gh repo clone vishnukg/fonts ${f.fonts} -- --quiet`]);
    assert.equal(fs.existsSync(f.fonts), true);
});

test('a failed clone warns without leaving the bootstrap in an error state', t => {
    // Arrange
    const f = fixture(t);
    f.tool('gh', `[ "$1" = repo ] && exit 1\nexit 0`);

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0);
    assert.match(result.stderr, /Could not clone/);
    assert.equal(fs.existsSync(f.fonts), false);
});

test('an existing clone is updated, and an offline update keeps the fonts already present', t => {
    // Arrange
    const f = fixture(t);
    fs.mkdirSync(path.join(f.fonts, '.git'), { recursive: true });
    fs.writeFileSync(path.join(f.fonts, 'BerkeleyMono-Regular.otf'), 'font bytes');
    f.tool('git', 'exit 0');
    f.tool('gh', 'echo "gh must not be consulted for an existing clone" >&2; exit 1');

    // Act
    const updated = f.run();

    // Assert
    assert.equal(updated.status, 0, updated.stderr);
    assert.match(updated.stdout, /Fonts up to date/);
    assert.deepEqual(f.calls(), [`git -C ${f.fonts} pull --ff-only --quiet`]);

    // Arrange
    f.tool('git', 'exit 1');

    // Act
    const offline = f.run();

    // Assert
    assert.equal(offline.status, 0, 'an offline machine must not fail the bootstrap');
    assert.match(offline.stderr, /keeping existing fonts/);
    assert.equal(fs.readFileSync(path.join(f.fonts, 'BerkeleyMono-Regular.otf'), 'utf8'), 'font bytes');
});

test('hand-copied fonts are left alone rather than replaced by a clone', t => {
    // Arrange
    // No .git: a pre-private-repo layout, or fonts the user placed by hand.
    const f = fixture(t);
    fs.mkdirSync(f.fonts, { recursive: true });
    fs.writeFileSync(path.join(f.fonts, 'BerkeleyMono-Regular.otf'), 'hand copied');
    f.tool('gh', 'exit 0');
    f.tool('git', 'exit 0');

    // Act
    const result = f.run();

    // Assert
    assert.equal(result.status, 0);
    assert.match(result.stderr, /not a git clone/);
    assert.deepEqual(f.calls(), [], 'neither gh nor git may touch a directory this script does not own');
    assert.equal(fs.readFileSync(path.join(f.fonts, 'BerkeleyMono-Regular.otf'), 'utf8'), 'hand copied');
});
