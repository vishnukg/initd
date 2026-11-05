// linux/scripts/brightness.sh: the brightness keys, the quick-settings slider
// and the bar's level read all steer the focused monitor through it.
// hyprctl, brightnessctl, ddcutil and qs are stubs that log their arguments,
// so no backlight or monitor is touched; ddcutil's `detect --brief` prints a
// captured two-display listing (laptop panel on bus 13, Dell on bus 14) and
// `getvcp 10 --brief` answers as the Dell does at 66%.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../../linux/scripts/brightness.sh', import.meta.url));

const DETECT = `Invalid display
   I2C bus:          /dev/i2c-13
   DRM connector:    card0-eDP-1
   drm_connector_id: 390
   Monitor:          LGD::

Display 1
   I2C bus:          /dev/i2c-14
   DRM connector:    card0-DP-1
   drm_connector_id: 399
   Monitor:          DEL:DELL U2725QE:3VSH584
`;

function monitors(focused) {
    return ['eDP-1', 'DP-1'].map((name) => `Monitor ${name} (ID 0):\n\t2560x1600@120.00000 at 0x0\n\tfocused: ${name === focused ? 'yes' : 'no'}\n\tdpmsStatus: 1\n`).join('\n');
}

function fixture({ focused = 'eDP-1', writeFails = false, slowWrite = false, level = 66 } = {}) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-brightness-'));
    const bin = path.join(root, 'bin');
    const log = path.join(root, 'calls.log');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(root, 'monitors.txt'), monitors(focused));
    fs.writeFileSync(path.join(root, 'detect.txt'), DETECT);
    const stub = (name, body) => fs.writeFileSync(path.join(bin, name), `#!/bin/bash\necho "${name} $*" >> "${log}"\n${body}\n`, { mode: 0o755 });
    stub('hyprctl', `cat "${root}/monitors.txt"`);
    stub('brightnessctl', 'exit 0');
    stub('qs', 'exit 0');
    stub('ddcutil', [
        `[ "$1" = detect ] && { cat "${root}/detect.txt"; exit 0; }`,
        `[ "$3" = getvcp ] && { echo "VCP 10 C ${level} 100"; exit 0; }`,
        slowWrite ? 'sleep 0.4' : 'true',
        `exit ${writeFails ? 1 : 0}`,
    ].join('\n'));
    const env = { PATH: `${bin}:/usr/bin:/bin`, XDG_RUNTIME_DIR: root };
    const run = (...args) => spawnSync('bash', [script, ...args], { encoding: 'utf8', env });
    const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean) : []);
    const published = () => fs.readFileSync(path.join(root, 'initd-brightness/level'), 'utf8');
    return { root, env, run, calls, published };
}

const notHyprctl = (c) => !c.startsWith('hyprctl');
const PING = 'qs ipc --any-display call bar refreshBrightness';

test('the laptop panel takes the backlight path; the keys ping the bar, the slider does not', () => {
    // Arrange
    const f = fixture({ focused: 'eDP-1' });

    // Act
    f.run('up');
    f.run('down');
    const slider = f.run('set', '40');

    // Assert
    assert.equal(slider.status, 0);
    assert.deepEqual(f.calls().filter(notHyprctl), [
        'brightnessctl -q set 5%+', PING,
        'brightnessctl --min-val=2 -q set 5%-', PING,
        'brightnessctl -q set 40%',
    ]);
});

test('an external monitor is asked its level once, then stepped with absolute writes on its bus', () => {
    // Arrange
    const f = fixture({ focused: 'DP-1', level: 66 });

    // Act
    const first = f.run('up');
    const second = f.run('down');

    // Assert
    assert.equal(first.status, 0, first.stderr);
    assert.equal(second.status, 0, second.stderr);
    assert.deepEqual(f.calls().filter(notHyprctl), [
        'ddcutil detect --brief',
        'ddcutil --bus 14 getvcp 10 --brief --sleep-multiplier .3',
        'ddcutil --bus 14 setvcp 10 71 --noverify --sleep-multiplier .3', PING,
        'ddcutil --bus 14 setvcp 10 66 --noverify --sleep-multiplier .3', PING,
    ]);
    assert.equal(f.published(), 'DP-1 66\n');
});

test('the slider sets an external level absolutely and publishes it without raising the indicator', () => {
    // Arrange
    const f = fixture({ focused: 'DP-1' });

    // Act
    const result = f.run('set', '40');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.ok(f.calls().includes('ddcutil --bus 14 setvcp 10 40 --noverify --sleep-multiplier .3'));
    assert.ok(!f.calls().includes(PING));
    assert.equal(f.published(), 'DP-1 40\n');
});

test('a step past the ends is clamped to 0..100', () => {
    // Arrange
    const high = fixture({ focused: 'DP-1', level: 98 });
    const low = fixture({ focused: 'DP-1', level: 3 });

    // Act
    high.run('up');
    low.run('down');

    // Assert
    assert.ok(high.calls().some((c) => c.includes('setvcp 10 100 ')));
    assert.ok(low.calls().some((c) => c.includes('setvcp 10 0 ')));
});

test('refresh re-asks the monitor even with a cached level, publishes, and writes nothing', () => {
    // Arrange: a stale cached level from an earlier step
    const f = fixture({ focused: 'DP-1', level: 30 });
    f.run('up'); // caches 35
    const before = f.calls().length;

    // Act
    const result = f.run('refresh');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    const after = f.calls().slice(before).filter(notHyprctl);
    assert.deepEqual(after, ['ddcutil --bus 14 getvcp 10 --brief --sleep-multiplier .3']);
    assert.equal(f.published(), 'DP-1 30\n');
});

test('a failed write drops the cached bus and level so the next press detects and asks again', () => {
    // Arrange
    const f = fixture({ focused: 'DP-1', writeFails: true });

    // Act
    const first = f.run('up');
    f.run('up');

    // Assert
    assert.equal(first.status, 1);
    assert.equal(f.calls().filter((c) => c === 'ddcutil detect --brief').length, 2);
    assert.equal(f.calls().filter((c) => c.includes('getvcp')).length, 2);
});

test('a key press that lands while a write is in flight is dropped', async () => {
    // Arrange
    const f = fixture({ focused: 'DP-1', slowWrite: true });

    // Act
    const first = new Promise((resolve) => spawn('bash', [script, 'up'], { env: f.env }).on('exit', resolve));
    while (!f.calls().some((c) => c.includes('setvcp'))) await new Promise((r) => setTimeout(r, 20));
    const second = f.run('up');
    await first;

    // Assert
    assert.equal(second.status, 0);
    assert.equal(f.calls().filter((c) => c.includes('setvcp')).length, 1);
});

test('a slider set that lands while a write is in flight waits and still lands', async () => {
    // Arrange
    const f = fixture({ focused: 'DP-1', slowWrite: true });

    // Act
    const first = new Promise((resolve) => spawn('bash', [script, 'up'], { env: f.env }).on('exit', resolve));
    while (!f.calls().some((c) => c.includes('setvcp'))) await new Promise((r) => setTimeout(r, 20));
    const slider = f.run('set', '20');
    await first;

    // Assert
    assert.equal(slider.status, 0, slider.stderr);
    assert.deepEqual(f.calls().filter((c) => c.includes('setvcp')).map((c) => c.split(' ')[5]), ['71', '20']);
    assert.equal(f.published(), 'DP-1 20\n');
});

for (const { name, args } of [
    { name: 'an unknown action', args: ['sideways'] },
    { name: 'set without a number', args: ['set', 'bright'] },
]) {
    test(`${name} is a usage error`, () => {
        assert.equal(fixture().run(...args).status, 2);
    });
}
