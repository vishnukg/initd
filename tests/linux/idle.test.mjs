// linux/scripts/idle.sh: hypridle's dim / undim / suspend-on-battery, run
// against stub brightnessctl, systemctl and playerctl and a fake
// /sys/class/power_supply, so nothing touches the real screen or suspends.
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

test('suspend-on-battery suspends a laptop on battery with nothing playing', () => {
    const f = fixture({ supplies: laptopOnBattery });
    f.run('suspend-on-battery');
    assert.ok(f.calls().includes('systemctl suspend'), f.calls().join('\n'));
});

test('suspend-on-battery stays awake on the barrel charger or USB-C power', () => {
    for (const charger of ['ADP1', 'ucsi-1']) {
        const supplies = structuredClone(laptopOnBattery);
        supplies[charger].online = 1;
        const f = fixture({ supplies });
        f.run('suspend-on-battery');
        assert.ok(!f.calls().includes('systemctl suspend'), charger);
    }
});

test('suspend-on-battery stays awake while media plays, and never on a machine without a battery', () => {
    const playing = fixture({ supplies: laptopOnBattery, playing: true });
    playing.run('suspend-on-battery');
    assert.ok(!playing.calls().includes('systemctl suspend'));
    const desktop = fixture({ supplies: { ADP1: { type: 'Mains', online: 0 } } });
    desktop.run('suspend-on-battery');
    assert.ok(!desktop.calls().includes('systemctl suspend'));
});

test('an unknown command is a usage error', () => {
    const f = fixture();
    assert.equal(f.run('bogus').status, 2);
});
