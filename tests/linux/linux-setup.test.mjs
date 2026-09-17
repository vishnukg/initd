import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dockerMenu } from '../../linux/scripts/docker-menu.mjs';
import { configureFirefox, findProfileDirectory } from '../../linux/scripts/firefox-profile.mjs';
import { configureLinks } from '../../linux/scripts/config-links.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
function fixture(t) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-linux-review-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    return {
        home,
        run(code, script = 'setup.sh') {
            const result = spawnSync('bash', ['-c', 'source "$1"\n' + code, 'fixture', path.join(root, 'linux', script)], {
                env: { ...process.env, HOME: home, BACKUP_ROOT: path.join(home, 'backup'), INITD_NODE: process.execPath },
                encoding: 'utf8', timeout: 10000,
            });
            return result;
        },
    };
}

test('Firefox managed files back up existing user settings and relink idempotently', t => {
    // Arrange
    const f = fixture(t);
    const profile = path.join(f.home, 'profile');
    fs.mkdirSync(path.join(profile, 'chrome'), { recursive: true });
    fs.writeFileSync(path.join(profile, 'user.js'), 'user settings');
    const registry = path.join(f.home, '.mozilla/firefox');
    fs.mkdirSync(registry, { recursive: true });
    fs.writeFileSync(path.join(registry, 'profiles.ini'), `[InstallTEST]\nDefault=${profile}\n`);
    const options = {
        home: f.home, configHome: path.join(f.home, '.config'), backupRoot: path.join(f.home, 'backup'),
        run: () => ({ status: 1 }), log() {}, warn() {},
    };

    // Act
    configureFirefox(options);
    configureFirefox(options);

    // Assert
    assert.equal(fs.readFileSync(path.join(f.home, 'backup/profile/user.js'), 'utf8'), 'user settings');
    assert.equal(fs.realpathSync(path.join(profile, 'user.js')), path.join(root, 'linux/configs/firefox/user.js'));
});

test('session links migrate the owned audio shell helper and preserve unrelated files', t => {
    // Arrange
    const f = fixture(t);
    const old = path.join(f.home, '.config/audio-ports.sh');
    fs.mkdirSync(path.dirname(old));
    const checkout = path.join(f.home, 'checkout');
    fs.mkdirSync(path.join(checkout, 'shared/configs/ghostty/.config/ghostty'), { recursive: true });
    fs.mkdirSync(path.join(checkout, 'linux'));
    fs.symlinkSync(path.join(root, 'linux/configs'), path.join(checkout, 'linux/configs'));
    fs.symlinkSync(path.join(root, 'linux/scripts'), path.join(checkout, 'linux/scripts'));
    const options = { root: checkout, home: f.home, backupRoot: path.join(f.home, 'backup'), log() {} };
    fs.symlinkSync(path.join(checkout, 'linux/scripts/audio-ports.sh'), old);

    // Act
    configureLinks(options);
    configureLinks(options);

    // Assert
    assert.equal(fs.existsSync(old), false);
    assert.equal(fs.readlinkSync(path.join(f.home, 'backup/.config/audio-ports.sh')), path.join(checkout, 'linux/scripts/audio-ports.sh'));
    assert.equal(fs.realpathSync(path.join(f.home, '.config/audio-ports.mjs')), path.join(root, 'linux/scripts/audio-ports.mjs'));

    // Arrange
    fs.writeFileSync(old, 'user helper');

    // Act
    configureLinks(options);

    // Assert
    assert.equal(fs.readFileSync(old, 'utf8'), 'user helper');
});

test('fresh Firefox profile lookup creates a profile and returns its resolved path', t => {
    // Arrange
    const { home } = fixture(t);
    const calls = [];
    const options = { home, configHome: path.join(home, '.config'), run(command, args) {
        calls.push([command, args]);
        const registry = path.join(home, '.mozilla/firefox');
        fs.mkdirSync(registry, { recursive: true });
        fs.writeFileSync(path.join(registry, 'profiles.ini'), '[InstallTEST]\nDefault=created\n');
        return { status: 0 };
    } };

    // Act
    const profile = findProfileDirectory(options);

    // Assert
    assert.deepEqual(calls, [['firefox', ['--headless', '--CreateProfile', 'default-release']]]);
    assert.equal(profile, path.join(home, '.mozilla/firefox/created'));
});

test('Firefox discovery respects legacy roots, XDG roots, and absolute paths', t => {
    // Arrange
    const { home } = fixture(t);
    const configHome = path.join(home, 'xdg');
    const legacy = path.join(home, '.mozilla/firefox');
    const xdg = path.join(configHome, 'mozilla/firefox');
    for (const directory of [legacy, xdg]) fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(path.join(legacy, 'profiles.ini'), '[InstallTEST]\nDefault=legacy\n');
    const absolute = path.join(home, 'custom profile');
    fs.writeFileSync(path.join(xdg, 'profiles.ini'), `[InstallTEST]\nDefault=${absolute}\n`);
    const options = { home, configHome, run() { assert.fail('existing profile must not launch Firefox'); } };

    // Act
    const findProfileDirectoryResult = findProfileDirectory(options);

    // Assert
    assert.equal(findProfileDirectoryResult, path.join(legacy, 'legacy'));

    // Arrange
    fs.unlinkSync(path.join(legacy, 'profiles.ini'));

    // Act
    const findProfileDirectoryResult2 = findProfileDirectory(options);

    // Assert
    assert.equal(findProfileDirectoryResult2, absolute);
});

test('Firefox zoom is skipped when running or process status is unavailable, and database errors are nonfatal', t => {
    // Arrange
    const { home } = fixture(t);
    const registry = path.join(home, '.mozilla/firefox');
    const profile = path.join(registry, 'profile');
    fs.mkdirSync(profile, { recursive: true });
    fs.writeFileSync(path.join(registry, 'profiles.ini'), '[InstallTEST]\nDefault=profile\n');
    const database = path.join(profile, 'content-prefs.sqlite');
    fs.writeFileSync(database, 'invalid database');
    const warnings = [];
    const options = { home, configHome: path.join(home, '.config'), backupRoot: path.join(home, 'backup'), log() {}, warn: message => warnings.push(message) };

    // Act
    for (const result of [{ status: 0 }, { error: new Error('pgrep missing') }, { status: 1 }]) {
        // Act
        const configureFirefoxResult = configureFirefox({ ...options, run: () => result });

        // Assert
        assert.equal(configureFirefoxResult, profile);
    }

    // Assert
    assert.match(warnings[0], /Firefox is running/);
    assert.match(warnings[1], /Cannot determine/);
    assert.match(warnings[2], /Could not update/);
    assert.equal(fs.readFileSync(database, 'utf8'), 'invalid database');
    assert.equal(fs.realpathSync(path.join(profile, 'user.js')), path.join(root, 'linux/configs/firefox/user.js'));
});

test('an unavailable Firefox install or failed initialization leaves the profile absent', t => {
    // Arrange
    const { home } = fixture(t);
    const warnings = [];
    const options = { home, configHome: path.join(home, '.config'), warn: message => warnings.push(message) };

    // Act
    const findProfileDirectoryResult = findProfileDirectory({ ...options, run: () => ({ error: { code: 'ENOENT' } }) });

    // Assert
    assert.equal(findProfileDirectoryResult, null);
    assert.deepEqual(warnings, []);

    // Act
    const findProfileDirectoryResult2 = findProfileDirectory({ ...options, run: () => ({ status: 1 }) });

    // Assert
    assert.equal(findProfileDirectoryResult2, null);
    assert.match(warnings[0], /could not initialize/);
    assert.equal(fs.existsSync(path.join(home, '.mozilla')), false);
});

test('Firefox-only setup calls the JavaScript setup workflow through mise', t => {
    // Arrange
    const f = fixture(t);
    const registry = path.join(f.home, '.mozilla/firefox');
    fs.mkdirSync(registry, { recursive: true });
    fs.writeFileSync(path.join(registry, 'profiles.ini'), '[InstallTEST]\nDefault=profile\n');

    // Act
    const result = f.run(`
mise() {
  [[ "$1" == -C && "$2" == "$ROOT_DIR" && "$3" == exec && "$4" == -- && "$5" == node ]] || return 98
  shift 5
  "$INITD_NODE" "$@"
}
main --firefox-only
`);

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(fs.realpathSync(path.join(registry, 'profile/user.js')), path.join(root, 'linux/configs/firefox/user.js'));
});

test('absent optional daemons do not abort Linux setup', t => {
    // Arrange
    const shell = fixture(t);
    const script = `
systemctl() {
    if [[ "$1" == show ]]; then echo not-found; return 0; fi
    if [[ "$2" == packagekit.service ]]; then echo masked; return 0; fi
    return 1
}
sudo() { echo 'unexpected sudo' >&2; return 99; }
disable_unused_daemons
`;

    // Act
    const result = shell.run(script);

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.doesNotMatch(result.stderr, /unexpected sudo/);
});

test('firmware marker detection consumes large input without pipefail false negatives', t => {
    // Arrange
    const shell = fixture(t);
    fs.writeFileSync(path.join(shell.home, 'module.ko'), 'Dell XPS WCL\n' + 'x'.repeat(2 * 1024 * 1024));

    // Act
    const result = shell.run('sof_sdw_module_has_dell_quirk "$HOME/module.ko"');

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
});

test('missing ALSA saved state does not prevent storing speaker settings', t => {
    // Arrange
    const shell = fixture(t);
    const script = `
amixer() { echo '  : values=off'; }
grep() { if [[ "$1" == -A1 ]]; then return 1; fi; command grep "$@"; }
sudo() { printf 'CALLED %s\\n' "$*"; }
disable_speaker_drc
`;

    // Act
    const result = shell.run(script);

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(result.stdout, /CALLED alsactl store/);
});

test('Docker bootstrap enables socket activation without stopping running containers', t => {
    // Arrange
    const shell = fixture(t);
    const script = `
rpm() { [[ "$2" == docker-ce ]]; }
id() { echo docker; }
sudo() {
    printf '%s\\n' "$*" >> "$HOME/docker-calls"
    if [[ "$*" == *'--now docker.service'* ]]; then touch "$HOME/stopped"; fi
}
ensure_docker
`;

    // Act
    const result = shell.run(script, 'bootstrap.sh');

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(result.stdout, /Docker Engine already installed/);
    assert.deepEqual(fs.readFileSync(path.join(shell.home, 'docker-calls'), 'utf8').trim().split('\n'), [
        'systemctl disable docker.service',
        'systemctl enable --now docker.socket',
    ]);
    assert.equal(fs.existsSync(path.join(shell.home, 'stopped')), false);
});

test('Docker menu reports a failed stop instead of announcing success', async () => {
    // Arrange
    const notices = [];
    const choices = ['web\tUp 2 hours', 'stop'];

    // Act
    const ok = await dockerMenu({
        run: async (_, args) => {
            if (args[0] === 'ps') return 'web\tUp 2 hours\n';
            throw new Error('permission denied');
        },
        choose: async () => choices.shift(),
        notify: async message => notices.push(message),
        launch: async () => assert.fail('unexpected terminal'),
    });

    // Assert
    assert.equal(ok, false);
    assert.deepEqual(notices, ['Docker action failed: permission denied']);
});

test('Docker menu distinguishes daemon failure from an empty container list', async () => {
    // Arrange
    const notices = [];
    const io = {
        run: async () => { throw new Error('daemon unavailable'); },
        choose: async () => assert.fail('unexpected menu'),
        notify: async message => notices.push(message),
    };

    // Act
    const dockerMenuResult = await dockerMenu(io);

    // Assert
    assert.equal(dockerMenuResult, false);
    assert.match(notices[0], /daemon unavailable/);

    // Act
    const dockerMenuResult2 = await dockerMenu({ ...io, run: async () => '' });

    // Assert
    assert.equal(dockerMenuResult2, true);
    assert.equal(notices[1], 'No running containers');
});

test('Docker menu launches logs and rejects selections outside its list', async () => {
    // Arrange
    const launched = [];
    const choices = ['web\tUp', 'logs'];
    const io = {
        run: async () => 'web\tUp\n', choose: async () => choices.shift(),
        notify: async () => {}, launch: async args => launched.push(args),
    };

    // Act
    const dockerMenuResult = await dockerMenu(io);

    // Assert
    assert.equal(dockerMenuResult, true);
    assert.deepEqual(launched, [['docker', 'logs', '-f', '--tail', '200', 'web']]);

    // Act
    const dockerMenuResult2 = await dockerMenu({ ...io, choose: async () => '--all' });

    // Assert
    assert.equal(dockerMenuResult2, false);
    assert.equal(launched.length, 1, 'an invalid selection must not launch another terminal');
});

test('desktop helpers handle missing executables without uncaught spawn errors', t => {
    // Arrange
    const f = fixture(t);
    const bin = path.join(f.home, 'bin');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'docker'), '#!/bin/sh\nprintf "web\\tUp\\n"\n', { mode: 0o755 });

    // Act
    const result = spawnSync(process.execPath, [path.join(root, 'linux/scripts/docker-menu.mjs')], {
        env: { ...process.env, PATH: bin }, encoding: 'utf8', timeout: 5000,
    });

    // Assert
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Docker action failed:.*rofi.*ENOENT/);
    assert.doesNotMatch(result.stderr, /Unhandled 'error'/);

    // Act
    const weather = spawnSync(process.execPath, ['--input-type=module', '-e',
        'globalThis.fetch = async () => ({ok:true,text:async()=>"City|Clear"}); await import(process.env.INITD_WEATHER);'], {
        env: { ...process.env, PATH: bin, INITD_WEATHER: path.join(root, 'linux/scripts/weather-popup.mjs') },
        encoding: 'utf8', timeout: 5000,
    });

    // Assert
    assert.equal(weather.status, 0);
    assert.match(weather.stderr, /notify-send:.*ENOENT/);
    assert.doesNotMatch(weather.stderr, /Unhandled 'error'/);
});
