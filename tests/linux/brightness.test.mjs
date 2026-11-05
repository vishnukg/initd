// linux/scripts/brightness.sh: the brightness keys step the focused monitor.
// hyprctl, brightnessctl, ddcutil and qs are stubs that log their arguments,
// so no backlight or monitor is touched; ddcutil's `detect --brief` prints a
// captured two-display listing (laptop panel on bus 13, Dell on bus 14).
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

function fixture({ focused = 'eDP-1', writeFails = false, slowWrite = false } = {}) {
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
    stub('ddcutil', `[ "$1" = detect ] && { cat "${root}/detect.txt"; exit 0; }; ${slowWrite ? 'sleep 0.4;' : ''} exit ${writeFails ? 1 : 0}`);
    const env = { PATH: `${bin}:/usr/bin:/bin`, XDG_RUNTIME_DIR: root };
    const run = (direction) => spawnSync('bash', [script, direction], { encoding: 'utf8', env });
    const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, 'utf8').trim().split('\n').filter(Boolean) : []);
    return { root, env, run, calls };
}

test('the laptop panel takes the backlight path and pings the bar', () => {
    // Arrange
    const f = fixture({ focused: 'eDP-1' });
    // Act
    f.run('up');
    f.run('down');
    // Assert
    const calls = f.calls().filter((c) => !c.startsWith('hyprctl'));
    assert.deepEqual(calls, [
        'brightnessctl -q set 5%+', 'qs ipc --any-display call bar refreshBrightness',
        'brightnessctl --min-val=2 -q set 5%-', 'qs ipc --any-display call bar refreshBrightness',
    ]);
});

test('an external monitor is stepped over DDC on its bus, with the bus detected once and cached', () => {
    const f = fixture({ focused: 'DP-1' });
    assert.equal(f.run('up').status, 0);
    assert.equal(f.run('down').status, 0);
    const ddc = f.calls().filter((c) => c.startsWith('ddcutil'));
    assert.deepEqual(ddc, [
        'ddcutil detect --brief',
        'ddcutil --bus 14 setvcp 10 + 5 --noverify --sleep-multiplier .3',
        'ddcutil --bus 14 setvcp 10 - 5 --noverify --sleep-multiplier .3',
    ]);
    assert.ok(!f.calls().some((c) => c.startsWith('brightnessctl')));
});

test('a failed write drops the cached bus so the next press detects again', () => {
    const f = fixture({ focused: 'DP-1', writeFails: true });
    assert.equal(f.run('up').status, 1);
    f.run('up');
    assert.equal(f.calls().filter((c) => c === 'ddcutil detect --brief').length, 2);
});

test('a press that lands while a write is in flight is dropped', async () => {
    const f = fixture({ focused: 'DP-1', slowWrite: true });
    const first = new Promise((resolve) => spawn('bash', [script, 'up'], { env: f.env }).on('exit', resolve));
    while (!f.calls().some((c) => c.includes('setvcp'))) await new Promise((r) => setTimeout(r, 20));
    const second = f.run('up');
    await first;
    assert.equal(second.status, 0);
    assert.equal(f.calls().filter((c) => c.includes('setvcp')).length, 1);
});

test('an unknown direction is a usage error', () => {
    assert.equal(fixture().run('sideways').status, 2);
});
