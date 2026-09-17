// The macOS bootstrap helpers, exercised by sourcing the production script and
// shadowing only the commands that would touch the machine. Sourcing is safe
// because main() is guarded; every helper here is otherwise unreachable from a
// test without running an entire bootstrap.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));

function fixture(t) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-macos-bootstrap-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    return {
        home,
        run(code) {
            return spawnSync('bash', ['-c', 'source "$1"\n' + code, 'fixture', path.join(root, 'macos/bootstrap.sh')], {
                env: { ...process.env, HOME: home, BACKUP_ROOT: path.join(home, 'backup'), NO_COLOR: '1' },
                encoding: 'utf8', timeout: 10000,
            });
        },
    };
}

test('sourcing the macOS bootstrap defines its helpers without running one', t => {
    // Arrange
    const f = fixture(t);

    // Act
    const result = f.run('echo "helper=$(type -t strip_cask_if_app_exists)"');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /helper=function/);
    assert.doesNotMatch(result.stdout, /Starting initd bootstrap/, 'sourcing must not begin a bootstrap');
});

test('a cask whose app is already installed outside Homebrew is dropped from the Brewfile copy', t => {
    // Arrange
    const f = fixture(t);
    const brewfile = path.join(f.home, 'Brewfile');
    const entries = [
        'brew "mise"',
        'cask "google-chrome"',
        // Same cask name inside another entry: only the whole-line entry goes.
        'cask "google-chrome-canary"',
        '# cask "google-chrome" (kept: a comment is not an entry)',
        'cask "ghostty"',
    ].join('\n') + '\n';
    fs.writeFileSync(brewfile, entries);

    // Act
    const result = f.run(`
brew() { return 1; }   # the cask is not installed through Homebrew
brewfile_tmp="${brewfile}"
mkdir -p "$HOME/Google Chrome.app"
strip_cask_if_app_exists google-chrome "$HOME/Google Chrome.app"
`);

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /Skipping google-chrome cask/);
    assert.deepEqual(fs.readFileSync(brewfile, 'utf8').trim().split('\n'), [
        'brew "mise"',
        'cask "google-chrome-canary"',
        '# cask "google-chrome" (kept: a comment is not an entry)',
        'cask "ghostty"',
    ]);
});

for (const { name, setup, reason } of [
    { name: 'the app is absent', setup: 'brew() { return 1; }', reason: 'nothing occupies the install path' },
    { name: 'Homebrew already owns the cask', setup: 'brew() { return 0; }\nmkdir -p "$HOME/Google Chrome.app"', reason: 'brew bundle can manage it' },
]) {
    test(`the Brewfile copy is left intact when ${name}`, t => {
        // Arrange
        const f = fixture(t);
        const brewfile = path.join(f.home, 'Brewfile');
        const entries = 'brew "mise"\ncask "google-chrome"\n';
        fs.writeFileSync(brewfile, entries);

        // Act
        const result = f.run(`
${setup}
brewfile_tmp="${brewfile}"
strip_cask_if_app_exists google-chrome "$HOME/Google Chrome.app"
`);

        // Assert
        assert.equal(result.status, 0, result.stderr);
        assert.equal(fs.readFileSync(brewfile, 'utf8'), entries, reason);
        assert.doesNotMatch(result.stderr, /Skipping/);
    });
}

test('stripping the only entry keeps the Brewfile rather than emptying it', t => {
    // Arrange
    // grep removes the last line, and an empty Brewfile would make `brew bundle`
    // a silent no-op that uninstalls nothing but installs nothing either.
    const f = fixture(t);
    const brewfile = path.join(f.home, 'Brewfile');
    fs.writeFileSync(brewfile, 'cask "google-chrome"\n');

    // Act
    const result = f.run(`
brew() { return 1; }
brewfile_tmp="${brewfile}"
mkdir -p "$HOME/Google Chrome.app"
strip_cask_if_app_exists google-chrome "$HOME/Google Chrome.app"
`);

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(brewfile, 'utf8'), 'cask "google-chrome"\n');
    assert.equal(fs.existsSync(`${brewfile}.tmp`), true,
        'the scratch file is cleaned up by the bootstrap EXIT trap, not by the helper');
});
