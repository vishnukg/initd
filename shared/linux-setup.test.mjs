import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dockerMenu } from '../linux/scripts/docker-menu.mjs';
import { configureFirefox, findProfileDirectory } from '../linux/scripts/firefox-profile.mjs';
import { configureLinks } from '../linux/scripts/config-links.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
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
            assert.equal(result.status, 0, result.stderr || result.stdout);
            return result.stdout;
        },
    };
}

test('Firefox managed files back up existing user settings and relink idempotently', t => {
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
    configureFirefox(options);
    configureFirefox(options);
    assert.equal(fs.readFileSync(path.join(f.home, 'backup/profile/user.js'), 'utf8'), 'user settings');
    assert.equal(fs.realpathSync(path.join(profile, 'user.js')), path.join(root, 'linux/configs/firefox/user.js'));
});

test('session links migrate the owned audio shell helper and preserve unrelated files', t => {
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
    configureLinks(options);
    configureLinks(options);
    assert.equal(fs.existsSync(old), false);
    assert.equal(fs.readlinkSync(path.join(f.home, 'backup/.config/audio-ports.sh')), path.join(checkout, 'linux/scripts/audio-ports.sh'));
    assert.equal(fs.realpathSync(path.join(f.home, '.config/audio-ports.mjs')), path.join(root, 'linux/scripts/audio-ports.mjs'));
    fs.writeFileSync(old, 'user helper');
    configureLinks(options);
    assert.equal(fs.readFileSync(old, 'utf8'), 'user helper');
});

test('fresh Firefox profile lookup creates a profile and returns its resolved path', t => {
    const f = fixture(t);
    const profile = findProfileDirectory({ home: f.home, configHome: path.join(f.home, '.config'), run(command, args) {
        assert.equal(command, 'firefox');
        assert.deepEqual(args, ['--headless', '--CreateProfile', 'default-release']);
        const registry = path.join(f.home, '.mozilla/firefox');
        fs.mkdirSync(registry, { recursive: true });
        fs.writeFileSync(path.join(registry, 'profiles.ini'), '[InstallTEST]\nDefault=created\n');
        return { status: 0 };
    } });
    assert.equal(profile, path.join(f.home, '.mozilla/firefox/created'));
});

test('Firefox discovery respects legacy roots, XDG roots, and absolute paths', t => {
    const { home } = fixture(t);
    const configHome = path.join(home, 'xdg');
    const legacy = path.join(home, '.mozilla/firefox');
    const xdg = path.join(configHome, 'mozilla/firefox');
    for (const directory of [legacy, xdg]) fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(path.join(legacy, 'profiles.ini'), '[InstallTEST]\nDefault=legacy\n');
    const absolute = path.join(home, 'custom profile');
    fs.writeFileSync(path.join(xdg, 'profiles.ini'), `[InstallTEST]\nDefault=${absolute}\n`);
    const options = { home, configHome, run() { assert.fail('existing profile must not launch Firefox'); } };
    assert.equal(findProfileDirectory(options), path.join(legacy, 'legacy'));
    fs.unlinkSync(path.join(legacy, 'profiles.ini'));
    assert.equal(findProfileDirectory(options), absolute);
});

test('Firefox zoom is skipped when running or process status is unavailable, and database errors are nonfatal', t => {
    const { home } = fixture(t);
    const registry = path.join(home, '.mozilla/firefox');
    const profile = path.join(registry, 'profile');
    fs.mkdirSync(profile, { recursive: true });
    fs.writeFileSync(path.join(registry, 'profiles.ini'), '[InstallTEST]\nDefault=profile\n');
    const database = path.join(profile, 'content-prefs.sqlite');
    fs.writeFileSync(database, 'invalid database');
    const warnings = [];
    const options = { home, configHome: path.join(home, '.config'), backupRoot: path.join(home, 'backup'), log() {}, warn: message => warnings.push(message) };
    for (const result of [{ status: 0 }, { error: new Error('pgrep missing') }, { status: 1 }]) {
        assert.equal(configureFirefox({ ...options, run: () => result }), profile);
    }
    assert.match(warnings[0], /Firefox is running/);
    assert.match(warnings[1], /Cannot determine/);
    assert.match(warnings[2], /Could not update/);
    assert.equal(fs.readFileSync(database, 'utf8'), 'invalid database');
    assert.equal(fs.realpathSync(path.join(profile, 'user.js')), path.join(root, 'linux/configs/firefox/user.js'));
});

test('an unavailable Firefox install or failed initialization leaves the profile absent', t => {
    const { home } = fixture(t);
    const warnings = [];
    const options = { home, configHome: path.join(home, '.config'), warn: message => warnings.push(message) };
    assert.equal(findProfileDirectory({ ...options, run: () => ({ error: { code: 'ENOENT' } }) }), null);
    assert.deepEqual(warnings, []);
    assert.equal(findProfileDirectory({ ...options, run: () => ({ status: 1 }) }), null);
    assert.match(warnings[0], /could not initialize/);
    assert.equal(fs.existsSync(path.join(home, '.mozilla')), false);
});

test('Firefox-only setup calls the JavaScript setup workflow through mise', t => {
    const f = fixture(t);
    const registry = path.join(f.home, '.mozilla/firefox');
    fs.mkdirSync(registry, { recursive: true });
    fs.writeFileSync(path.join(registry, 'profiles.ini'), '[InstallTEST]\nDefault=profile\n');
    f.run(`
mise() {
  [[ "$1" == -C && "$2" == "$ROOT_DIR" && "$3" == exec && "$4" == -- && "$5" == node ]] || return 98
  shift 5
  "$INITD_NODE" "$@"
}
main --firefox-only
`);
    assert.equal(fs.realpathSync(path.join(registry, 'profile/user.js')), path.join(root, 'linux/configs/firefox/user.js'));
});

test('absent optional daemons do not abort Linux setup', t => {
    fixture(t).run(`
systemctl() {
    if [[ "$1" == show ]]; then echo not-found; return 0; fi
    if [[ "$2" == packagekit.service ]]; then echo masked; return 0; fi
    return 1
}
sudo() { echo 'unexpected sudo' >&2; return 99; }
disable_unused_daemons
`);
});

test('firmware marker detection consumes large input without pipefail false negatives', t => {
    const f = fixture(t);
    fs.writeFileSync(path.join(f.home, 'module.ko'), 'Dell XPS WCL\n' + 'x'.repeat(2 * 1024 * 1024));
    f.run('sof_sdw_module_has_dell_quirk "$HOME/module.ko"');
});

test('missing ALSA saved state does not prevent storing speaker settings', t => {
    const out = fixture(t).run(`
amixer() { echo '  : values=off'; }
grep() { if [[ "$1" == -A1 ]]; then return 1; fi; command grep "$@"; }
sudo() { printf 'CALLED %s\\n' "$*"; }
disable_speaker_drc
`);
    assert.match(out, /CALLED alsactl store/);
});

test('Docker bootstrap enables socket activation without stopping running containers', t => {
    const out = fixture(t).run(`
rpm() { [[ "$2" == docker-ce ]]; }
id() { echo docker; }
sudo() { printf 'CALLED %s\\n' "$*" >&2; }
ensure_docker
`, 'bootstrap.sh');
    assert.match(out, /Docker Engine already installed/);
    // A second run with a strict mock rejects the destructive form directly.
    fixture(t).run(`
rpm() { [[ "$2" == docker-ce ]]; }
id() { echo docker; }
sudo() {
    if [[ "$*" == *'--now docker.service'* ]]; then touch "$HOME/stopped"; fi
}
ensure_docker
test ! -e "$HOME/stopped"
`, 'bootstrap.sh');
});

test('Docker menu reports a failed stop instead of announcing success', async () => {
    const notices = [];
    const choices = ['web\tUp 2 hours', 'stop'];
    const ok = await dockerMenu({
        run: async (_, args) => {
            if (args[0] === 'ps') return 'web\tUp 2 hours\n';
            throw new Error('permission denied');
        },
        choose: async () => choices.shift(),
        notify: async message => notices.push(message),
        launch: async () => assert.fail('unexpected terminal'),
    });
    assert.equal(ok, false);
    assert.deepEqual(notices, ['Docker action failed: permission denied']);
});

test('Docker menu distinguishes daemon failure from an empty container list', async () => {
    const notices = [];
    const io = {
        run: async () => { throw new Error('daemon unavailable'); },
        choose: async () => assert.fail('unexpected menu'),
        notify: async message => notices.push(message),
    };
    assert.equal(await dockerMenu(io), false);
    assert.match(notices[0], /daemon unavailable/);
    assert.equal(await dockerMenu({ ...io, run: async () => '' }), true);
    assert.equal(notices[1], 'No running containers');
});

test('Docker menu launches logs and rejects selections outside its list', async () => {
    const launched = [];
    const choices = ['web\tUp', 'logs'];
    const io = {
        run: async () => 'web\tUp\n', choose: async () => choices.shift(),
        notify: async () => {}, launch: async args => launched.push(args),
    };
    assert.equal(await dockerMenu(io), true);
    assert.deepEqual(launched, [['docker', 'logs', '-f', '--tail', '200', 'web']]);
    assert.equal(await dockerMenu({ ...io, choose: async () => '--all' }), false);
});

test('desktop helpers handle missing executables without uncaught spawn errors', t => {
    const f = fixture(t);
    const bin = path.join(f.home, 'bin');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'docker'), '#!/bin/sh\nprintf "web\\tUp\\n"\n', { mode: 0o755 });
    const result = spawnSync(process.execPath, [path.join(root, 'linux/scripts/docker-menu.mjs')], {
        env: { ...process.env, PATH: bin }, encoding: 'utf8', timeout: 5000,
    });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Docker action failed:.*rofi.*ENOENT/);
    assert.doesNotMatch(result.stderr, /Unhandled 'error'/);
    const weather = spawnSync(process.execPath, ['--input-type=module', '-e',
        'globalThis.fetch = async () => ({ok:true,text:async()=>"City|Clear"}); await import(process.env.INITD_WEATHER);'], {
        env: { ...process.env, PATH: bin, INITD_WEATHER: path.join(root, 'linux/scripts/weather-popup.mjs') },
        encoding: 'utf8', timeout: 5000,
    });
    assert.equal(weather.status, 0);
    assert.match(weather.stderr, /notify-send:.*ENOENT/);
    assert.doesNotMatch(weather.stderr, /Unhandled 'error'/);
});
