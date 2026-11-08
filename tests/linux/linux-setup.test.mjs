import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dockerMenu } from '../../linux/scripts/docker-menu.mjs';
import { configureFirefox, findProfileDirectory, setDefaultBrowser, BROWSER } from '../../linux/scripts/firefox-profile.mjs';
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

test('Firefox setup links user.js and userChrome.css, backing up an existing one, and relinks idempotently', t => {
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
    assert.equal(fs.realpathSync(path.join(profile, 'chrome/userChrome.css')), path.join(root, 'linux/configs/firefox/chrome/userChrome.css'));
    assert.deepEqual(fs.readdirSync(path.join(profile, 'chrome')), ['userChrome.css']);
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
    assert.equal(fs.realpathSync(path.join(f.home, '.config/theme.mjs')), path.join(root, 'linux/scripts/theme.mjs'));
    assert.equal(fs.realpathSync(path.join(f.home, '.config/wallpaper.mjs')), path.join(root, 'linux/scripts/wallpaper.mjs'));
    assert.equal(fs.realpathSync(path.join(f.home, '.config/idle.sh')), path.join(root, 'linux/scripts/idle.sh'));
    assert.equal(fs.realpathSync(path.join(f.home, '.config/brightness.sh')), path.join(root, 'linux/scripts/brightness.sh'));

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
    assert.equal(calls.length, 1);
    assert.deepEqual([calls[0][0], calls[0][1][0], calls[0][1][1], calls[0][1][3]], ['firefox', '--headless', '--screenshot', 'about:blank']);
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
    const legacyDefault = findProfileDirectory(options);

    // Assert
    assert.equal(legacyDefault, path.join(legacy, 'legacy'));

    // Arrange
    fs.unlinkSync(path.join(legacy, 'profiles.ini'));

    // Act
    const absoluteXdgDefault = findProfileDirectory(options);

    // Assert
    assert.equal(absoluteXdgDefault, absolute);
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
    const options = { home, configHome: path.join(home, '.config'), log() {}, warn: message => warnings.push(message) };

    // Act
    for (const result of [{ status: 0 }, { error: new Error('pgrep missing') }, { status: 1 }]) {
        // Act
        const profileDirectory = configureFirefox({ ...options, run: () => result });

        // Assert
        assert.equal(profileDirectory, profile);
    }

    // Assert
    assert.match(warnings[0], /Firefox is running/);
    assert.match(warnings[1], /Cannot determine/);
    assert.match(warnings[2], /Could not update/);
    assert.equal(fs.readFileSync(database, 'utf8'), 'invalid database');
});

test('an unavailable Firefox install or failed initialization leaves the profile absent', t => {
    // Arrange
    const { home } = fixture(t);
    const warnings = [];
    const options = { home, configHome: path.join(home, '.config'), warn: message => warnings.push(message) };

    // Act
    const withoutFirefoxInstalled = findProfileDirectory({ ...options, run: () => ({ error: { code: 'ENOENT' } }) });

    // Assert
    assert.equal(withoutFirefoxInstalled, null);
    assert.deepEqual(warnings, []);

    // Act
    const afterFailedInitialization = findProfileDirectory({ ...options, run: () => ({ status: 1 }) });

    // Assert
    assert.equal(afterFailedInitialization, null);
    assert.match(warnings[0], /could not initialize/);
    assert.equal(fs.existsSync(path.join(home, '.mozilla')), false);
});

function recorder(answers) {
    const calls = [];
    const run = (command, args) => {
        calls.push([command, ...args]);
        if (command === 'xdg-settings') return answers[args[0]];
        return { status: 1 };
    };
    return { calls, run };
}

function installedFirefox(t) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-firefox-desktop-'));
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const desktop = path.join(directory, BROWSER);
    fs.writeFileSync(desktop, '[Desktop Entry]\n');
    return desktop;
}

test('Firefox becomes the default browser when something else is', t => {
    // Arrange
    const desktop = installedFirefox(t);
    const { calls, run } = recorder({ get: { status: 0, stdout: 'brave-browser.desktop\n' }, set: { status: 0 } });
    const warnings = [];

    // Act
    setDefaultBrowser({ desktop, run, log() {}, warn: message => warnings.push(message) });

    // Assert
    assert.deepEqual(calls.at(-1), ['xdg-settings', 'set', 'default-web-browser', BROWSER]);
    assert.deepEqual(warnings, []);
});

test('Default browser is left alone when Firefox already holds it', t => {
    // Arrange
    const desktop = installedFirefox(t);
    const { calls, run } = recorder({ get: { status: 0, stdout: `${BROWSER}\n` } });

    // Act
    setDefaultBrowser({ desktop, run, log() {}, warn() {} });

    // Assert
    assert.deepEqual(calls, [['xdg-settings', 'get', 'default-web-browser']]);
});

test('Default browser is not touched while Firefox is not installed, and a failed change only warns', t => {
    // Arrange
    const desktop = installedFirefox(t);
    const { calls, run } = recorder({ get: { status: 1 }, set: { status: 3, stderr: 'xdg-settings: boom\n' } });
    const warnings = [];

    // Act
    setDefaultBrowser({ desktop: path.join(path.dirname(desktop), 'missing.desktop'), run, log() {}, warn() {} });

    // Assert
    assert.deepEqual(calls, []);

    // Act
    setDefaultBrowser({ desktop, run, log() {}, warn: message => warnings.push(message) });

    // Assert
    assert.deepEqual(warnings, ['Could not make Firefox the default browser: xdg-settings: boom']);
});

test('Firefox-only setup calls the JavaScript setup workflow through mise', t => {
    // Arrange
    const f = fixture(t);
    const registry = path.join(f.home, '.mozilla/firefox');
    fs.mkdirSync(registry, { recursive: true });
    fs.writeFileSync(path.join(registry, 'profiles.ini'), '[InstallTEST]\nDefault=profile\n');

    const bin = path.join(f.home, 'bin');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'xdg-settings'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });

    // Act
    const result = f.run(`
export PATH="$HOME/bin:$PATH"
mise() {
  [[ "$1" == -C && "$2" == "$ROOT_DIR" && "$3" == exec && "$4" == node@lts && "$5" == -- && "$6" == node ]] || return 98
  shift 6
  "$INITD_NODE" "$@"
}
main --firefox-only
`);

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    // Which zoom warning appears depends on whether this host has Firefox open.
    assert.match(result.stderr + result.stdout, /Firefox (is running|preferences are not initialized)/);
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

test('lid switch drop-in installs once, reloads logind without a restart, and is idempotent', t => {
    // Arrange
    const shell = fixture(t);
    const dropins = path.join(shell.home, 'logind.conf.d');
    const calls = path.join(shell.home, 'calls');
    const script = `
export LOGIND_DROPIN_DIR=${JSON.stringify(dropins)}
sudo() {
    echo "$*" >> ${JSON.stringify(calls)}
    if [[ "$1" == install ]]; then "$@"; fi
}
configure_lid_switch
configure_lid_switch
`;

    // Act
    const result = shell.run(script);

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(
        fs.readFileSync(path.join(dropins, 'initd-lid-switch.conf'), 'utf8'),
        fs.readFileSync(path.join(root, 'linux/configs/logind/initd-lid-switch.conf'), 'utf8'),
    );
    assert.match(fs.readFileSync(path.join(dropins, 'initd-lid-switch.conf'), 'utf8'), /^HandleLidSwitchExternalPower=ignore$/m);
    const sudoCalls = fs.readFileSync(calls, 'utf8').trim().split('\n');
    assert.equal(sudoCalls.length, 2, 'the second run must not invoke sudo');
    assert.match(sudoCalls[1], /^systemctl kill -s HUP systemd-logind\.service$/);
    assert.ok(sudoCalls.every(call => !/restart/.test(call)));
});

test('wakeup udev rule installs once, applies to the USB root hubs now, and is idempotent', t => {
    // Arrange
    const shell = fixture(t);
    const rules = path.join(shell.home, 'rules.d');
    const calls = path.join(shell.home, 'calls');
    const script = `
export UDEV_RULES_DIR=${JSON.stringify(rules)}
sudo() {
    echo "$*" >> ${JSON.stringify(calls)}
    if [[ "$1" == install ]]; then "$@"; fi
}
configure_wakeup_sources
configure_wakeup_sources
`;

    // Act
    const result = shell.run(script);

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const installed = fs.readFileSync(path.join(rules, '90-initd-wakeup.rules'), 'utf8');
    assert.equal(installed, fs.readFileSync(path.join(root, 'linux/configs/udev/90-initd-wakeup.rules'), 'utf8'));
    assert.match(installed, /SUBSYSTEM=="usb".*ATTR\{bDeviceClass\}=="09".*ATTR\{power\/wakeup\}="enabled"/);
    assert.doesNotMatch(installed, /^ACTION.*SUBSYSTEM=="pci"/m, 'the Bluetooth controller never woke the machine');
    const sudoCalls = fs.readFileSync(calls, 'utf8').trim().split('\n');
    assert.equal(sudoCalls.length, 3, 'the second run must not invoke sudo');
    assert.equal(sudoCalls[1], 'udevadm control --reload');
    assert.match(sudoCalls[2], /^udevadm trigger --action=add --subsystem-match=usb /);
});

test('initramfs Bluetooth drop-in installs once, rebuilds every kernel, and is idempotent', t => {
    // Arrange
    const shell = fixture(t);
    const dropins = path.join(shell.home, 'dracut.conf.d');
    const calls = path.join(shell.home, 'calls');
    const script = `
export DRACUT_DROPIN_DIR=${JSON.stringify(dropins)}
sudo() {
    echo "$*" >> ${JSON.stringify(calls)}
    if [[ "$1" == install ]]; then "$@"; fi
}
configure_initramfs_bluetooth
configure_initramfs_bluetooth
`;

    // Act
    const result = shell.run(script);

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const installed = fs.readFileSync(path.join(dropins, 'initd-bluetooth.conf'), 'utf8');
    assert.equal(installed, fs.readFileSync(path.join(root, 'linux/configs/dracut/initd-bluetooth.conf'), 'utf8'));
    assert.match(installed, /^add_dracutmodules\+=" bluetooth "$/m);
    const sudoCalls = fs.readFileSync(calls, 'utf8').trim().split('\n');
    assert.equal(sudoCalls.length, 2, 'the second run must not invoke sudo');
    assert.equal(sudoCalls[1], 'dracut -f --regenerate-all');
});

test('Docker bootstrap enables socket activation without stopping running containers', t => {
    // Arrange
    const shell = fixture(t);
    // systemctl is mocked as a machine where Docker was just installed: without
    // it the real systemd answers, and on a host that already runs Docker
    // socket-activated ensure_docker correctly takes its no-sudo shortcut.
    const script = `
rpm() { [[ "$2" == docker-ce ]]; }
id() { echo docker; }
systemctl() {
    case "$1" in
        is-enabled) [[ "$2" == docker.service ]] && echo enabled || echo disabled ;;
        is-active) return 3 ;;
    esac
}
sudo() {
    printf '%s\\n' "$*" >> "$HOME/docker-calls"
    if [[ "$*" == *'--now docker.service'* ]]; then touch "$HOME/stopped"; fi
}
queue_docker
install_queued_packages
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

test('a Docker already socket-activated is left alone without sudo', t => {
    // Arrange
    const shell = fixture(t);
    const script = `
id() { echo docker; }
systemctl() {
    case "$1" in
        is-enabled) [[ "$2" == docker.socket ]] && echo enabled || echo disabled ;;
        is-active) return 0 ;;
    esac
}
sudo() { echo 'unexpected sudo' >&2; return 99; }
ensure_docker
`;

    // Act
    const result = shell.run(script, 'bootstrap.sh');

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.doesNotMatch(result.stderr, /unexpected sudo/);
    assert.match(result.stdout, /docker\.socket already enabled/);
});

// rpm -q mock for the batched missing_rpms call: `installed` decides each name,
// absent names are reported the way rpm does, on stdout.
const rpmMock = installed => `
rpm() {
    if [[ "$1" == -E ]]; then echo 44; return; fi
    [[ "$1" == -q ]] && shift
    local name status=0
    for name in "$@"; do
        if ${installed}; then echo "\${name}-1.0-1.fc44.x86_64"; else echo "package \${name} is not installed"; status=1; fi
    done
    return "\${status}"
}`;

for (const state of ['fresh', 'restricted', 'configured', 'non-intel']) {
    test(`video codecs handle a ${state} Fedora install`, t => {
        // Arrange
        const f = fixture(t);
        const installed = state === 'configured';

        // Act
        const result = f.run(`
${rpmMock(`case "\${name}" in
            rpmfusion-*-release) [[ '${state}' != fresh ]] ;;
            libva-intel-media-driver) [[ '${state}' == restricted ]] ;;
            intel-media-driver|ffmpeg-free|libavcodec-freeworld|libva-utils) ${installed} ;;
            *) false ;;
        esac`)}
dnf() {
    ${installed} && printf '%s\\n' rpmfusion-free rpmfusion-free-updates rpmfusion-nonfree rpmfusion-nonfree-updates \\
        | sed 's/$/ RPM Fusion/'
}
has_intel_gpu() { [[ '${state}' != non-intel ]]; }
sudo() { printf '%s\\n' "$*" >> "$HOME/codec-calls"; }
touch "$HOME/codec-calls"
ensure_video_codecs
install_queued_packages
`, 'bootstrap.sh');

        // Assert
        assert.equal(result.status, 0, result.stderr || result.stdout);
        const calls = fs.readFileSync(path.join(f.home, 'codec-calls'), 'utf8').trim().split('\n').filter(Boolean);
        if (installed) {
            assert.deepEqual(calls, []);
            assert.match(result.stdout, /Video codecs already installed/);
            return;
        }
        const releases = calls.filter(call => call.includes('rpmfusion-'));
        if (state === 'fresh') {
            assert.equal(releases.filter(call => call.startsWith('dnf install')).length, 1, 'both release RPMs in one call');
            assert.match(releases[0], /rpmfusion-free-release-44\.noarch\.rpm .*rpmfusion-nonfree-release-44\.noarch\.rpm/);
        } else {
            assert.equal(calls.some(call => call.includes('-release-44.noarch.rpm')), false);
        }
        assert.ok(calls.some(call => /config-manager setopt rpmfusion-free.enabled=1/.test(call)));
        assert.equal(calls.includes('dnf swap -y libva-intel-media-driver intel-media-driver'), state === 'restricted');
        const driver = state === 'fresh' ? 'intel-media-driver ' : '';
        assert.deepEqual(calls.filter(call => call.startsWith('dnf install -y --setopt')),
            [`dnf install -y --setopt=install_weak_deps=False ${driver}ffmpeg-free libavcodec-freeworld libva-utils`]);
        assert.ok(calls.every(call => !call.includes('--allowerasing')));
    });
}

test('a fresh Fedora machine installs every queued package in one dnf transaction', t => {
    // Arrange
    const f = fixture(t);

    // Act
    const result = f.run(`
${rpmMock('false')}
dnf() { return 0; }
has_intel_gpu() { false; }
command() { [[ "$1" == -v ]] && return 1; builtin command "$@"; }
require_command() { :; }
sudo() { printf '%s\\n' "$*" >> "$HOME/dnf-calls"; [[ "$1 $2" == "tee "* ]] && cat >/dev/null; return 0; }
queue_listed_packages
ensure_video_codecs
ensure_gh
ensure_1password
ensure_brave
queue_docker
install_queued_packages
install_queued_packages
`, 'bootstrap.sh');

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const calls = fs.readFileSync(path.join(f.home, 'dnf-calls'), 'utf8').trim().split('\n');
    const installs = calls.filter(call => call.startsWith('dnf install -y --setopt'));
    assert.equal(installs.length, 1, calls.join('\n'));
    for (const pkg of ['hyprland', 'kitty', 'fish', '@c-development', 'ffmpeg-free', 'gh', '1password',
        'brave-browser', 'docker-ce', 'docker-compose-plugin']) {
        assert.ok(installs[0].split(' ').includes(pkg), `${pkg} missing from: ${installs[0]}`);
    }
    assert.ok(calls.every(call => !/^dnf (group )?install -y (gh|1password|brave-browser|docker-ce|c-development)\b/.test(call)));
    assert.match(result.stdout, /No dnf packages to install/, 'the queue is emptied after installing');
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
    const onDaemonFailure = await dockerMenu(io);

    // Assert
    assert.equal(onDaemonFailure, false);
    assert.match(notices[0], /daemon unavailable/);

    // Act
    const onEmptyContainerList = await dockerMenu({ ...io, run: async () => '' });

    // Assert
    assert.equal(onEmptyContainerList, true);
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
    const afterChoosingLogs = await dockerMenu(io);

    // Assert
    assert.equal(afterChoosingLogs, true);
    assert.deepEqual(launched, [['docker', 'logs', '-f', '--tail', '200', 'web']]);

    // Act
    const afterAnInvalidSelection = await dockerMenu({ ...io, choose: async () => '--all' });

    // Assert
    assert.equal(afterAnInvalidSelection, false);
    assert.equal(launched.length, 1, 'an invalid selection must not launch another terminal');
});

test('desktop helpers handle missing executables without uncaught spawn errors', t => {
    // Arrange
    const f = fixture(t);
    const bin = path.join(f.home, 'bin');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'docker'), '#!/bin/sh\nprintf "web\\tUp\\n"\n', { mode: 0o755 });

    // Act: 20s spawn limits are a ceiling, not a wait - a healthy run takes
    // ~80ms, but a loaded parallel suite once pushed one past 5s.
    const result = spawnSync(process.execPath, [path.join(root, 'linux/scripts/docker-menu.mjs')], {
        env: { ...process.env, PATH: bin }, encoding: 'utf8', timeout: 20000,
    });

    // Assert
    assert.ifError(result.error);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Docker action failed:.*rofi.*ENOENT/);
    assert.doesNotMatch(result.stderr, /Unhandled 'error'/);

    // Act
    const weather = spawnSync(process.execPath, ['--input-type=module', '-e',
        'globalThis.fetch = async () => ({ok:true,text:async()=>"City|Clear"}); await import(process.env.INITD_WEATHER);'], {
        env: { ...process.env, PATH: bin, INITD_WEATHER: path.join(root, 'linux/scripts/weather-popup.mjs') },
        encoding: 'utf8', timeout: 20000,
    });

    // Assert
    assert.ifError(weather.error);
    assert.equal(weather.status, 0);
    assert.match(weather.stderr, /notify-send:.*ENOENT/);
    assert.doesNotMatch(weather.stderr, /Unhandled 'error'/);
});

test('fisher is not left waiting on a scripted bootstrap stdin that never closes', t => {
    // Arrange
    // fisher reads plugin names from any non-tty stdin until EOF. The stub fish
    // reads stdin the same way, and the fifo keeps a writer open, so without
    // the redirect this run would block until the spawn timeout.
    const f = fixture(t);

    // Act
    const result = f.run(`
fish() { cat > /dev/null; printf 'fisher-synced\\n'; }
getent() { printf '%s:x:1000:1000::/home/u:fish\\n' "$2"; }
sudo() { :; }
gh() { return 1; }
mkfifo "$HOME/stdin"
exec 3<> "$HOME/stdin" 0< "$HOME/stdin"
ensure_fish
`, 'bootstrap.sh');

    // Assert
    assert.equal(result.status, 0, result.error?.message ?? result.stderr);
    assert.match(result.stdout, /fisher-synced/);
});

for (const { name, writable, ruleInstalled, expectedSudo } of [
    { name: 'already accessible i2c devices need nothing', writable: true, ruleInstalled: true, expectedSudo: [] },
    { name: 'root-only i2c devices get the udev add re-triggered once', writable: false, ruleInstalled: true, expectedSudo: ['udevadm trigger --subsystem-match=i2c-dev --action=add'] },
    { name: 'root-only i2c devices without ddcutil are left alone', writable: false, ruleInstalled: false, expectedSudo: [] },
]) {
    test(`i2c access: ${name}`, t => {
        // Arrange
        const shell = fixture(t);
        const devices = path.join(shell.home, 'dev');
        const rules = path.join(shell.home, 'rules.d');
        const calls = path.join(shell.home, 'calls');
        fs.mkdirSync(devices);
        fs.mkdirSync(rules);
        for (const n of [13, 14])
            fs.writeFileSync(path.join(devices, `i2c-${n}`), '', { mode: writable ? 0o600 : 0o000 });
        if (ruleInstalled)
            fs.writeFileSync(path.join(rules, '60-ddcutil-i2c.rules'), 'SUBSYSTEM=="i2c-dev", TAG+="uaccess"\n');
        const script = `
export I2C_DEV_GLOB=${JSON.stringify(path.join(devices, 'i2c-*'))}
export UDEV_SYSTEM_RULES_DIR=${JSON.stringify(rules)}
sudo() { echo "$*" >> ${JSON.stringify(calls)}; }
grant_i2c_access
`;

        // Act
        const result = shell.run(script);

        // Assert
        assert.equal(result.status, 0, result.stderr || result.stdout);
        const sudoCalls = fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8').trim().split('\n') : [];
        assert.deepEqual(sudoCalls, expectedSudo);
    });
}

test('i2c access: no devices at all is nothing to do', t => {
    // Arrange
    const shell = fixture(t);
    const script = `
export I2C_DEV_GLOB=${JSON.stringify(path.join(shell.home, 'none/i2c-*'))}
sudo() { echo "unexpected sudo $*" >&2; exit 1; }
grant_i2c_access
`;

    // Act
    const result = shell.run(script);

    // Assert
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(result.stdout, /nothing to do/i);
});

for (const { name, current, expectedSet } of [
    { name: 'an empty plugin list gets all three tray plugins disabled', current: '@as []', expectedSet: "['!StatusIcon', '!ShowConnected', '!StatusNotifierItem']" },
    { name: 'a list with only StatusIcon off (the old step) gains the other two', current: "['!StatusIcon']", expectedSet: "['!StatusIcon', '!ShowConnected', '!StatusNotifierItem']" },
    { name: 'a list with all three off is left alone', current: "['!StatusIcon', '!ShowConnected', '!StatusNotifierItem']", expectedSet: null },
]) {
    test(`blueman headless: ${name}`, t => {
        // Arrange
        const shell = fixture(t);
        const calls = path.join(shell.home, 'calls');
        const script = `
gsettings() {
    echo "$*" >> ${JSON.stringify(calls)}
    case "$1" in
        list-schemas) echo org.blueman.general ;;
        get) echo ${JSON.stringify(current)} ;;
    esac
}
pgrep() { return 1; }
configure_blueman_headless
`;

        // Act
        const result = shell.run(script);

        // Assert
        assert.equal(result.status, 0, result.stderr || result.stdout);
        const sets = fs.readFileSync(calls, 'utf8').trim().split('\n').filter(c => c.startsWith('set '));
        assert.deepEqual(sets, expectedSet === null ? [] : [`set org.blueman.general plugin-list ${expectedSet}`]);
    });
}
