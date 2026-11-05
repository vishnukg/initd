// linux/scripts/idle.sh: hypridle's dim / undim / can-suspend, run against
// stub brightnessctl and playerctl and a fake /sys/class/power_supply, so
// nothing touches the real screen. can-suspend is a condition_cmd: its exit
// status is the answer, and hypridle itself runs `systemctl suspend`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../../linux/scripts/idle.sh', import.meta.url));

function fixture({ brightness = 44, supplies = {}, playing = false } = {}) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-idle-'));
    const bin = path.join(root, 'bin');
    const power = path.join(root, 'power_supply');
    const log = path.join(root, 'calls.log');
    fs.mkdirSync(bin);
    fs.mkdirSync(power);
    for (const [name, files] of Object.entries(supplies)) {
        fs.mkdirSync(path.join(power, name));
        for (const [file, value] of Object.entries(files)) fs.writeFileSync(path.join(power, name, file), `${value}\n`);
    }
    const stub = (name, body) => fs.writeFileSync(path.join(bin, name), `#!/bin/bash\necho "${name} $*" >> "${log}"\n${body}\n`, { mode: 0o755 });
    stub('brightnessctl', `[ "$1" = -m ] && echo "intel_backlight,backlight,1,${brightness}%,100"; exit 0`);
    stub('systemctl', 'exit 0');
    stub('playerctl', playing ? 'echo Playing' : 'echo Paused');
    const run = (command) => spawnSync('bash', [script, command], {
        encoding: 'utf8',
        env: { PATH: `${bin}:/usr/bin:/bin`, XDG_RUNTIME_DIR: root, IDLE_POWER_SUPPLY: power },
    });
    const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n') : []);
    return { run, calls };
}

const laptopOnBattery = { ADP1: { type: 'Mains', online: 0 }, BAT0: { type: 'Battery' }, 'ucsi-1': { type: 'USB', online: 0 } };

test('dim saves and drops to 20%, and undim restores only after a dim', () => {
    // Arrange
    const f = fixture({ brightness: 44 });
    // Act
    f.run('dim');
    f.run('undim');
    f.run('undim');
    // Assert: one save-and-set, one restore -- the second undim is a no-op.
    const changes = f.calls().filter((c) => !c.includes(' -m'));
    assert.deepEqual(changes, ['brightnessctl -q -s set 20%', 'brightnessctl -q -r']);
});

test('dim never brightens a screen already at or below 20%', () => {
    const f = fixture({ brightness: 12 });
    f.run('dim');
    f.run('undim');
    assert.deepEqual(f.calls().filter((c) => !c.includes(' -m')), []);
});

test('can-suspend allows a laptop on battery with nothing playing', () => {
    const f = fixture({ supplies: laptopOnBattery });
    const result = f.run('can-suspend');
    assert.equal(result.status, 0, result.stderr);
    // The decision is the exit status; the script never suspends by itself.
    assert.ok(!f.calls().some((c) => c.startsWith('systemctl')), f.calls().join('\n'));
});

test('can-suspend refuses on the barrel charger or USB-C power', () => {
    for (const charger of ['ADP1', 'ucsi-1']) {
        const supplies = structuredClone(laptopOnBattery);
        supplies[charger].online = 1;
        const f = fixture({ supplies });
        assert.equal(f.run('can-suspend').status, 1, charger);
    }
});

test('can-suspend refuses while media plays, and always on a machine without a battery', () => {
    const playing = fixture({ supplies: laptopOnBattery, playing: true });
    assert.equal(playing.run('can-suspend').status, 1);
    const desktop = fixture({ supplies: { ADP1: { type: 'Mains', online: 0 } } });
    assert.equal(desktop.run('can-suspend').status, 1);
});

test('an unknown command is a usage error', () => {
    const f = fixture();
    assert.equal(f.run('bogus').status, 2);
});

// lock: hyprlock is a stub that exits with the next status listed in a file,
// so a crash (139), a SIGTERM (143), an unlock (0) and a refusal (1) can be
// played in order without a compositor.
function lockFixture(statuses, { running = false } = {}) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-lock-'));
    const bin = path.join(root, 'bin');
    const queue = path.join(root, 'statuses');
    const log = path.join(root, 'calls.log');
    fs.mkdirSync(bin);
    fs.writeFileSync(queue, statuses.join('\n') + '\n');
    const stub = (name, body) => fs.writeFileSync(path.join(bin, name), `#!/bin/bash\necho "${name} $*" >> "${log}"\n${body}\n`, { mode: 0o755 });
    stub('hyprlock', `s=$(head -n1 "${queue}"); sed -i 1d "${queue}"; exit "\${s:-0}"`);
    stub('pgrep', running ? 'exit 0' : 'exit 1');
    const env = { PATH: `${bin}:/usr/bin:/bin`, XDG_RUNTIME_DIR: root, LOCK_RESTART_DELAY: '0' };
    const run = () => spawnSync('bash', [script, 'lock'], { encoding: 'utf8', env });
    const launches = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n') : [])
        .filter((c) => c.startsWith('hyprlock'));
    return { root, env, run, launches };
}

test('lock restarts hyprlock after a crash or a kill, and stops at the unlock', () => {
    // Arrange: segfault, then SIGTERM (a TTY pkill), then a normal unlock.
    const f = lockFixture([139, 143, 0, 0]);
    // Act
    const result = f.run();
    // Assert: three launches, every one without the fade-in, none after the unlock.
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(f.launches(), Array(3).fill('hyprlock --no-fade-in'));
});

test('lock does not retry an ordinary failure, such as another client holding the lock', () => {
    const f = lockFixture([1, 0]);
    f.run();
    assert.equal(f.launches().length, 1);
});

test('lock gives up after five restarts of a client that keeps crashing', () => {
    const f = lockFixture(Array(10).fill(134));
    f.run();
    assert.equal(f.launches().length, 6);
});

test('lock starts nothing while a hyprlock is already running', () => {
    const f = lockFixture([0], { running: true });
    f.run();
    assert.deepEqual(f.launches(), []);
});

test('lock runs one supervisor at a time', async () => {
    // Arrange: the first client stays up until released, the way a real lock
    // screen does until the password is typed.
    const f = lockFixture([0]);
    const release = path.join(f.root, 'release');
    fs.writeFileSync(path.join(f.root, 'bin/hyprlock'),
        `#!/bin/bash\necho "hyprlock $*" >> "${path.join(f.root, 'calls.log')}"\nwhile [ ! -e "${release}" ]; do sleep 0.05; done\n`, { mode: 0o755 });
    const { spawn } = await import('node:child_process');
    const first = new Promise((resolve) => spawn('bash', [script, 'lock'], { env: f.env }).on('exit', resolve));
    while (f.launches().length === 0) await new Promise((r) => setTimeout(r, 20));
    // Act: a second lock-session while the first is showing.
    const second = f.run();
    fs.writeFileSync(release, '');
    await first;
    // Assert
    assert.equal(second.status, 0);
    assert.equal(f.launches().length, 1);
});
