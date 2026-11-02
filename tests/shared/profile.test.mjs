// shared/lib/profile.sh: the OS/profile summary every bootstrap prints first,
// and the personal/work answer shared/managed-links.sh gates dev box links on.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));

function fixture(t, email) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-profile-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    // The summary warns unless the repo sits at ~/.config/initd, so place it there.
    const repo = path.join(home, '.config/initd');
    fs.mkdirSync(path.join(repo, 'shared/configs/git'), { recursive: true });
    fs.mkdirSync(path.join(repo, 'shared/lib'), { recursive: true });
    for (const name of ['logging.sh', 'profile.sh']) {
        fs.copyFileSync(path.join(root, 'shared/lib', name), path.join(repo, 'shared/lib', name));
    }
    if (email) fs.writeFileSync(path.join(repo, 'shared/configs/git/local.gitconfig'), `[user]\n\temail = ${email}\n`);
    return {
        repo,
        summary: (rootDir = repo) => spawnSync('bash', ['-c', [
            'set -euo pipefail', 'ROOT_DIR=$1',
            'source "$ROOT_DIR/shared/lib/logging.sh"', 'source "$ROOT_DIR/shared/lib/profile.sh"',
            'log_bootstrap_summary linux',
        ].join('\n'), 'profile', rootDir], { env: { PATH: process.env.PATH, HOME: home, NO_COLOR: '1' }, encoding: 'utf8' }),
    };
}

for (const [name, email, expected] of [
    ['personal', 'vishnukg@gmail.com', /Profile:\s+personal \(vishnukg@gmail\.com\)/],
    ['work', 'me@work.example', /Profile:\s+work \(me@work\.example\)/],
    ['unset', undefined, /Profile:\s+not set yet/],
]) {
    test(`the bootstrap summary names the OS and a ${name} profile`, t => {
        // Arrange
        const f = fixture(t, email);

        // Act
        const result = f.summary();

        // Assert
        assert.equal(result.status, 0, result.stderr);
        assert.match(result.stdout, /initd linux bootstrap/);
        assert.match(result.stdout, /OS:\s+\S.*\(\w+\)/);
        assert.match(result.stdout, expected);
        assert.equal(result.stderr, '', 'a repo at ~/.config/initd needs no path warning');
    });
}

test('a repo outside ~/.config/initd is warned about, since git cannot find local.gitconfig', t => {
    // Arrange
    const f = fixture(t, 'vishnukg@gmail.com');
    const elsewhere = path.join(path.dirname(path.dirname(f.repo)), 'src/initd');
    fs.mkdirSync(path.dirname(elsewhere), { recursive: true });
    fs.renameSync(f.repo, elsewhere);

    // Act
    const result = f.summary(elsewhere);

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /not ~\/\.config\/initd/);
});
