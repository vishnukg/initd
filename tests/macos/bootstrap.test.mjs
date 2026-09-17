// The macOS bootstrap helpers, exercised by sourcing the production script and
// shadowing only the commands that would touch the machine. Sourcing is safe
// because main() is guarded; every helper here is otherwise unreachable from a
// test without running an entire bootstrap.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));

// Every command stub is a symlink to this one script, and its behaviour arrives
// in the environment as INITD_STUB_<command>. macOS spends ~250ms scanning each
// newly written executable the first time it runs - per file, so a script per
// stub would cost more than the rest of the suite put together - but it resolves
// a symlink to the file it has already scanned.
const stubRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-macos-stubs-'));
after(() => fs.rmSync(stubRoot, { recursive: true, force: true }));
const stubScript = path.join(stubRoot, 'stub.sh');
fs.writeFileSync(stubScript, [
    '#!/bin/bash',
    'name="${0##*/}"',
    `printf '%s\\n' "$name $*" >> "$INITD_STUB_LOG"`,
    'behavior="INITD_STUB_${name}"',
    'eval "${!behavior:-}"',
    '',
].join('\n'), { mode: 0o755 });

function fixture(t) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-macos-bootstrap-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    const bin = path.join(home, 'bin');
    const callLog = path.join(home, 'calls.log');
    const behaviors = {};
    fs.mkdirSync(bin, { recursive: true });
    return {
        home,
        bin,
        // Stub executables rather than shell functions: ensure_colima_service
        // reaches brew through `env -u TMUX`, which resolves a file on PATH and
        // never sees a function, and ensure_tmux_terminfo calls infocmp and tic
        // by absolute path. Every stub records its own invocation, so a step
        // that must NOT run is asserted by absence rather than by side effect.
        stub(name, body = '', directory = bin) {
            fs.mkdirSync(directory, { recursive: true });
            fs.symlinkSync(stubScript, path.join(directory, name));
            behaviors[`INITD_STUB_${name}`] = body;
        },
        calls() {
            return fs.existsSync(callLog) ? fs.readFileSync(callLog, 'utf8').trim().split('\n') : [];
        },
        run(code, env = {}) {
            return spawnSync('bash', ['-c', 'source "$1"\n' + code, 'fixture', path.join(root, 'macos/bootstrap.sh')], {
                env: {
                    ...process.env, HOME: home, BACKUP_ROOT: path.join(home, 'backup'),
                    NO_COLOR: '1', PATH: `${bin}:${process.env.PATH}`,
                    INITD_STUB_LOG: callLog, ...behaviors, ...env,
                },
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

// --- ensure_local_fonts -----------------------------------------------------
// The licensed fonts are COPIED rather than linked because CoreText refuses to
// register a font reached through a symlink, so "did it copy?" and "did it stop
// copying once installed?" are both load-bearing.

function fontsRepo(f, files) {
    const shared = path.join(f.home, 'repo/shared');
    const source = path.join(shared, 'fonts/berkeley-mono');
    fs.mkdirSync(source, { recursive: true });
    for (const [name, contents] of Object.entries(files)) fs.writeFileSync(path.join(source, name), contents);
    return { shared, source, installed: path.join(f.home, 'Library/Fonts') };
}
const installFonts = shared => `SHARED_DIR=${JSON.stringify(shared)}\nensure_local_fonts`;

test('licensed fonts are copied into ~/Library/Fonts as real files', t => {
    // Arrange
    const f = fixture(t);
    const fonts = fontsRepo(f, { 'BerkeleyMono-Regular.otf': 'regular-bytes', 'BerkeleyMono-Bold.otf': 'bold-bytes' });

    // Act
    const result = f.run(installFonts(fonts.shared));

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Installed 2 font file\(s\)/);
    for (const [name, contents] of [['BerkeleyMono-Regular.otf', 'regular-bytes'], ['BerkeleyMono-Bold.otf', 'bold-bytes']]) {
        const installed = path.join(fonts.installed, name);
        assert.equal(fs.readFileSync(installed, 'utf8'), contents);
        assert.equal(fs.lstatSync(installed).isFile(), true, `${name} must be a copy, not a link CoreText will not register`);
    }
});

test('a second run copies nothing and leaves the installed fonts untouched', t => {
    // Arrange
    const f = fixture(t);
    const fonts = fontsRepo(f, { 'BerkeleyMono-Regular.otf': 'regular-bytes' });
    const installed = path.join(fonts.installed, 'BerkeleyMono-Regular.otf');
    assert.equal(f.run(installFonts(fonts.shared)).status, 0);
    const afterFirstRun = fs.statSync(installed).mtimeMs;

    // Act
    const result = f.run(installFonts(fonts.shared));

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /already installed/);
    assert.equal(fs.statSync(installed).mtimeMs, afterFirstRun);
});

test('only a stale font is refreshed, and the current one is left where it is', t => {
    // Arrange
    const f = fixture(t);
    const fonts = fontsRepo(f, { 'BerkeleyMono-Regular.otf': 'new-bytes', 'BerkeleyMono-Bold.otf': 'bold-bytes' });
    assert.equal(f.run(installFonts(fonts.shared)).status, 0);
    fs.writeFileSync(path.join(fonts.installed, 'BerkeleyMono-Regular.otf'), 'old-bytes');
    const boldAtInstall = fs.statSync(path.join(fonts.installed, 'BerkeleyMono-Bold.otf')).mtimeMs;

    // Act
    const result = f.run(installFonts(fonts.shared));

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Installed 1 font file\(s\)/);
    assert.equal(fs.readFileSync(path.join(fonts.installed, 'BerkeleyMono-Regular.otf'), 'utf8'), 'new-bytes');
    assert.equal(fs.statSync(path.join(fonts.installed, 'BerkeleyMono-Bold.otf')).mtimeMs, boldAtInstall);
});

test('a machine without the private fonts skips the step and creates no font directory', t => {
    // Arrange
    // The fonts repo is gitignored and absent until shared/lib/fonts.sh has run
    // with gh auth, so this is the state of every unauthenticated bootstrap.
    const f = fixture(t);
    const shared = path.join(f.home, 'repo/shared');

    // Act
    const result = f.run(installFonts(shared));

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /No machine-local fonts to install/);
    assert.equal(fs.existsSync(path.join(f.home, 'Library/Fonts')), false);
});

test('a fonts directory holding no OTFs installs nothing, not a file named *.otf', t => {
    // Arrange
    // The glob is unquoted, so without the existence guard the literal pattern
    // would be copied into ~/Library/Fonts as a font.
    const f = fixture(t);
    const fonts = fontsRepo(f, { 'README.md': 'licence terms', 'BerkeleyMono-Regular.ttf': 'wrong format' });

    // Act
    const result = f.run(installFonts(fonts.shared));

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(fs.readdirSync(fonts.installed), []);
});

// --- ensure_tmux_terminfo ---------------------------------------------------
// macOS's system tmux-256color predates Smulx, so Neovim inside tmux degrades
// undercurl to a plain underline. Every path here fails soft: a machine without
// Homebrew ncurses still finishes its bootstrap.

function ncurses(f) {
    const prefix = path.join(f.home, 'ncurses');
    return { prefix, bin: path.join(prefix, 'bin'), locate: `brew() { printf '%s\\n' ${JSON.stringify(prefix)}; }` };
}

test('a machine without Homebrew ncurses is warned rather than left half-compiled', t => {
    // Arrange
    const f = fixture(t);
    const brew = ncurses(f);
    fs.mkdirSync(brew.bin, { recursive: true });

    // Act
    const result = f.run(`${brew.locate}\nensure_tmux_terminfo`);

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /Homebrew ncurses not found/);
    assert.match(result.stderr, /undercurl/, 'the warning names the symptom, not just the missing tool');
    assert.equal(fs.existsSync(path.join(f.home, '.terminfo')), false);
});

test('a local terminfo entry that already carries Smulx is not recompiled', t => {
    // Arrange
    const f = fixture(t);
    const brew = ncurses(f);
    f.stub('infocmp', `printf 'tmux-256color|tmux with 256 colors,\\n\\tSmulx=set,\\n'`, brew.bin);
    f.stub('tic', 'exit 1', brew.bin);

    // Act
    const result = f.run(`${brew.locate}\nensure_tmux_terminfo`);

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /already carries Smulx/);
    assert.deepEqual(f.calls().filter(call => call.startsWith('tic')), []);
});

for (const { name, probe } of [
    { name: 'no local entry exists yet', probe: 'exit 1' },
    { name: 'the local entry predates Smulx', probe: `printf 'tmux-256color|tmux with 256 colors,\\n'` },
]) {
    test(`the Homebrew entry is compiled into ~/.terminfo when ${name}`, t => {
        // Arrange
        const f = fixture(t);
        const brew = ncurses(f);
        // The -A probe reads ~/.terminfo; the bare call reads Homebrew's entry.
        f.stub('infocmp', `if [[ "$2" == "-A" ]]; then\n${probe}\nfi\nprintf 'HOMEBREW-ENTRY\\n'`, brew.bin);
        f.stub('tic', `mkdir -p "$HOME/.terminfo"\ncat > "$HOME/.terminfo/compiled"`, brew.bin);

        // Act
        const result = f.run(`${brew.locate}\nensure_tmux_terminfo`);

        // Assert
        assert.equal(result.status, 0, result.stderr);
        assert.match(result.stdout, /Compiled Homebrew ncurses's tmux-256color terminfo/);
        assert.equal(fs.readFileSync(path.join(f.home, '.terminfo/compiled'), 'utf8'), 'HOMEBREW-ENTRY\n',
            'tic compiles what infocmp read from Homebrew, not the stale system entry');
        // Pipeline order is not deterministic: assert membership, not position.
        assert.ok(f.calls().includes(`tic -x -o ${path.join(f.home, '.terminfo')} -`),
            `tic compiles into ~/.terminfo: ${f.calls().join(', ')}`);
    });
}

test('a failed compile warns instead of claiming the terminfo was updated', t => {
    // Arrange
    const f = fixture(t);
    const brew = ncurses(f);
    f.stub('infocmp', `if [[ "$2" == "-A" ]]; then exit 1; fi\nprintf 'HOMEBREW-ENTRY\\n'`, brew.bin);
    f.stub('tic', 'cat > /dev/null\nexit 1', brew.bin);

    // Act
    const result = f.run(`${brew.locate}\nensure_tmux_terminfo`);

    // Assert
    assert.equal(result.status, 0, result.stderr, 'a terminfo that will not compile must not fail the bootstrap');
    assert.match(result.stderr, /Failed to compile tmux-256color terminfo/);
    assert.doesNotMatch(result.stdout, /Compiled/);
});

test('an infocmp that fails mid-pipeline is reported even though tic succeeds', t => {
    // Arrange
    // Without pipefail the pipeline would report tic's success and the machine
    // would keep a truncated entry that the next run treats as compiled.
    const f = fixture(t);
    const brew = ncurses(f);
    f.stub('infocmp', 'exit 1', brew.bin);
    f.stub('tic', `mkdir -p "$HOME/.terminfo"\ncat > "$HOME/.terminfo/compiled"`, brew.bin);

    // Act
    const result = f.run(`${brew.locate}\nensure_tmux_terminfo`);

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /Failed to compile tmux-256color terminfo/);
    assert.doesNotMatch(result.stdout, /Compiled/);
    assert.ok(f.calls().some(call => call.startsWith('tic')), 'the pipeline ran; its status came from infocmp');
});

// --- ensure_colima_service --------------------------------------------------
// Ownership of the running instance is the whole point: the launchd job runs
// `colima start -f`, which exits immediately when an instance is already up,
// and launchd would then respawn it in a loop.

const brewServices = ({ running = false, startStatus = 0 } = {}) => `
case "$*" in
  "services info colima --json") printf '{"name":"colima","running": ${running}}\\n' ;;
  "services start colima") exit ${startStatus} ;;
esac
`;

test('a colima login service that is already running is left alone', t => {
    // Arrange
    const f = fixture(t);
    f.stub('brew', brewServices({ running: true }));
    f.stub('colima');

    // Act
    const result = f.run('ensure_colima_service');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /already running/);
    assert.deepEqual(f.calls(), ['brew services info colima --json']);
});

test('a manually started colima is stopped before the login service takes it over', t => {
    // Arrange
    const f = fixture(t);
    f.stub('brew', brewServices({ running: false }));
    f.stub('colima', 'exit 0');   // `colima status` succeeds: an instance is up

    // Act
    const result = f.run('ensure_colima_service');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.calls(), [
        'brew services info colima --json',
        'colima status',
        'colima stop',
        'brew services start colima',
    ]);
});

test('a colima that is not running is started without a needless stop', t => {
    // Arrange
    const f = fixture(t);
    f.stub('brew', brewServices({ running: false }));
    f.stub('colima', 'exit 1');   // `colima status` fails: no instance

    // Act
    const result = f.run('ensure_colima_service');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.calls(), ['brew services info colima --json', 'colima status', 'brew services start colima']);
    assert.match(result.stdout, /Enabling colima as a login service/);
});

test('a brew services start that fails stops the bootstrap and names the log', t => {
    // Arrange
    const f = fixture(t);
    f.stub('brew', brewServices({ running: false, startStatus: 1 }));
    f.stub('colima', 'exit 1');

    // Act
    const result = f.run('ensure_colima_service');

    // Assert
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Failed to start colima via brew services/);
    assert.match(result.stderr, /colima\.log/);
});

test('brew services never inherits TMUX from the shell running the bootstrap', t => {
    // Arrange
    // Homebrew refuses to manage services when it inherits TMUX, so bootstrap
    // strips only that marker to stay runnable from an existing tmux shell.
    const f = fixture(t);
    f.stub('brew', `printf 'TMUX=%s\\n' "\${TMUX-unset}" >> "$INITD_STUB_LOG"\n${brewServices({ running: false })}`);
    f.stub('colima', 'exit 1');

    // Act
    const result = f.run('ensure_colima_service', { TMUX: '/private/tmp/tmux-501/default,1234,0' });

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.calls().filter(call => call.startsWith('TMUX=')), ['TMUX=unset', 'TMUX=unset']);
});

// --- ensure_gh_auth ---------------------------------------------------------

test('an authenticated gh is reported without opening a login flow', t => {
    // Arrange
    const f = fixture(t);
    f.stub('gh', 'exit 0');

    // Act
    const result = f.run('ensure_gh_auth');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /gh auth check done/);
    assert.deepEqual(f.calls(), ['gh auth token']);
});

test('an unauthenticated non-interactive bootstrap warns and carries on', t => {
    // Arrange
    // This is the path that pairs with fonts.sh skipping the private repo:
    // neither step may block or fail a scripted bootstrap.
    const f = fixture(t);
    f.stub('gh', `case "$*" in "auth token") exit 1 ;; esac`);

    // Act
    const result = f.run('ensure_gh_auth');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /not authenticated, and bootstrap is not running interactively/);
    assert.match(result.stdout, /gh auth login later/, 'the next step goes to stdout; only the warning is on stderr');
    assert.deepEqual(f.calls(), ['gh auth token']);
});

// --- setup_git_profile ------------------------------------------------------

function gitRepo(f, email) {
    const shared = path.join(f.home, 'repo/shared');
    fs.mkdirSync(path.join(shared, 'configs/git'), { recursive: true });
    if (email) fs.writeFileSync(path.join(shared, 'configs/git/local.gitconfig'), `[user]\n\temail = ${email}\n`);
    return `SHARED_DIR=${JSON.stringify(shared)}\nsetup_git_profile`;
}

test('an existing work override is reported rather than asked for again', t => {
    // Arrange
    const f = fixture(t);
    f.stub('mise');
    const configure = gitRepo(f, 'engineer@work.example');

    // Act
    const result = f.run(configure);

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /already configured \(override email: engineer@work\.example\)/);
    assert.deepEqual(f.calls(), []);
});

test('a non-interactive bootstrap leaves the Git identity to a later run', t => {
    // Arrange
    // git-profile.mjs prompts, so calling it here would hang a scripted run.
    const f = fixture(t);
    f.stub('mise');
    const configure = gitRepo(f, null);

    // Act
    const result = f.run(configure);

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /Git identity needs setup/);
    assert.match(result.stdout, /git-profile\.mjs personal or work later/, 'the next step goes to stdout; only the warning is on stderr');
    assert.deepEqual(f.calls(), []);
});

// --- macos/update.sh --------------------------------------------------------
// update.sh runs main unconditionally, so only the argument handling that
// precedes ensure_homebrew_env can be exercised without touching the machine.

function update(...args) {
    return spawnSync('bash', [path.join(root, 'macos/update.sh'), ...args],
        { encoding: 'utf8', env: { ...process.env, NO_COLOR: '1' }, timeout: 10000 });
}

test('update.sh explains itself without updating anything', () => {
    // Arrange
    const args = ['--help'];

    // Act
    const result = update(...args);

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Usage: update\.sh/);
    assert.doesNotMatch(result.stdout, /Updating Homebrew metadata/);
});

test('update.sh rejects an unknown argument before running a single update', () => {
    // Arrange
    const args = ['upgrade'];

    // Act
    const result = update(...args);

    // Assert
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Unknown argument: upgrade/);
    assert.match(result.stderr, /Usage: update\.sh/);
    assert.doesNotMatch(result.stdout, /Updating Homebrew metadata/);
});
