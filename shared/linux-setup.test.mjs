import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dockerMenu } from '../linux/scripts/docker-menu.mjs';

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
    f.run('FIREFOX_PROFILE_RESOLVED=1; FIREFOX_PROFILE_DIR="$HOME/profile"; link_firefox_profile; link_firefox_profile');
    assert.equal(fs.readFileSync(path.join(f.home, 'backup/profile/user.js'), 'utf8'), 'user settings');
    assert.equal(fs.realpathSync(path.join(profile, 'user.js')), path.join(root, 'linux/configs/firefox/user.js'));
});

test('session links migrate the owned audio shell helper and preserve unrelated files', t => {
    const f = fixture(t);
    const old = path.join(f.home, '.config/audio-ports.sh');
    fs.mkdirSync(path.dirname(old));
    fs.symlinkSync(path.join(root, 'linux/scripts/audio-ports.sh'), old);
    f.run('link_session_scripts; link_session_scripts');
    assert.equal(fs.existsSync(old), false);
    assert.equal(fs.readlinkSync(path.join(f.home, 'backup/.config/audio-ports.sh')), path.join(root, 'linux/scripts/audio-ports.sh'));
    assert.equal(fs.realpathSync(path.join(f.home, '.config/audio-ports.mjs')), path.join(root, 'linux/scripts/audio-ports.mjs'));
    fs.writeFileSync(old, 'user helper');
    f.run('link_session_scripts');
    assert.equal(fs.readFileSync(old, 'utf8'), 'user helper');
});

test('fresh Firefox profile lookup returns only the path, not progress messages', t => {
    const f = fixture(t);
    const out = f.run(`
firefox() {
    mkdir -p "$HOME/.mozilla/firefox"
    printf '[InstallTEST]\\nDefault=created\\n' > "$HOME/.mozilla/firefox/profiles.ini"
}
mise() { [[ "$1" == -C && "$2" == "$ROOT_DIR" ]] || return 98; shift 5; "$INITD_NODE" "$@"; }
cd "$HOME"
find_firefox_profile_dir
`);
    assert.equal(out.trim(), path.join(f.home, '.mozilla/firefox/created'));
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
