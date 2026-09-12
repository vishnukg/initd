import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { nightLight, scheduledState } from '../linux/scripts/night-light-toggle.mjs';

function fixture({ active = false, stray = false, stuck = false, skipStart = false, failStop = false } = {}) {
    const calls = [];
    let waits = 0;
    return {
        calls,
        get waits() { return waits; },
        run(command, args) {
            calls.push([command, ...args]);
            if (command === 'pgrep') return { status: stray ? 0 : 1 };
            if (command === 'systemctl') {
                if (args[1] === 'is-active') return { status: active ? 0 : 3 };
                if (args[1] === 'start') active = !skipStart;
                if (args[1] === 'stop') {
                    if (failStop) return { status: 1 };
                    active = false;
                }
            }
            return { status: 0 };
        },
        async wait(milliseconds) {
            assert.equal(milliseconds, 100);
            waits++;
            if (!stuck) stray = false;
        },
    };
}

test('night-light schedule handles midnight and both boundaries', () => {
    for (const hour of [0, 6, 19, 23]) assert.equal(scheduledState(hour), 'on');
    for (const hour of [7, 12, 18]) assert.equal(scheduledState(hour), 'off');
    for (const hour of [-1, 24, 1.5, NaN]) assert.throws(() => scheduledState(hour), /between 0 and 23/);
});

test('night-light on/off are idempotent and toggle follows service state', async () => {
    const io = fixture();
    await nightLight(['on'], io);
    await nightLight(['on'], io);
    await nightLight([], io);
    await nightLight(['off'], io);
    assert.equal(io.calls.filter(call => call[0] === 'systemctl' && call[2] === 'start').length, 1);
    assert.equal(io.calls.filter(call => call[0] === 'systemctl' && call[2] === 'stop').length, 1);
    assert.deepEqual(io.calls.filter(call => call[0] === 'notify-send').map(call => call.at(-1)), ['On (4500K)', 'Off']);
    assert.equal(io.calls.filter(call => call[0] === 'qs').length, 4);
});

test('night-light auto applies the requested hour', async () => {
    const io = fixture();
    await nightLight(['auto'], { ...io, hour: 19 });
    await nightLight(['auto'], { ...io, hour: 7 });
    assert.deepEqual(io.calls.filter(call => call[0] === 'notify-send').map(call => call.at(-1)), ['On (4500K)', 'Off']);
});

test('night-light waits for stray gamma controllers before starting', async () => {
    const io = fixture({ stray: true });
    await nightLight(['on'], io);
    assert.equal(io.waits, 1);
    assert.ok(io.calls.findIndex(call => call[0] === 'pkill')
        < io.calls.findIndex(call => call[0] === 'systemctl' && call[2] === 'start'));
});

test('a stuck gamma controller prevents a second start and still refreshes the bar', async () => {
    const io = fixture({ stray: true, stuck: true });
    await assert.rejects(nightLight(['on'], io), /refusing to start/);
    assert.equal(io.waits, 80);
    assert.ok(!io.calls.some(call => call[0] === 'systemctl' && call[2] === 'start'));
    assert.ok(!io.calls.some(call => call[0] === 'notify-send'));
    assert.equal(io.calls.at(-1)[0], 'qs');
});

test('a skipped service or failed stop never announces success', async () => {
    const skipped = fixture({ skipStart: true });
    await nightLight(['on'], skipped);
    assert.ok(!skipped.calls.some(call => call[0] === 'notify-send'));
    const failed = fixture({ active: true, failStop: true });
    await assert.rejects(nightLight(['off'], failed), /systemctl failed/);
    assert.ok(!failed.calls.some(call => call[0] === 'notify-send'));
    assert.equal(failed.calls.at(-1)[0], 'qs');
});

test('night-light rejects invalid arguments and tolerates missing optional tools', async () => {
    const io = fixture();
    await assert.rejects(nightLight(['bad'], io), /Usage:/);
    await assert.rejects(nightLight(['on', 'off'], io), /Usage:/);
    assert.deepEqual(io.calls, []);
    await nightLight(['on'], { ...io, run(command, args) {
        if (['notify-send', 'qs'].includes(command)) return { error: new Error('missing') };
        return io.run(command, args);
    } });
    await assert.rejects(nightLight(['on'], { run: () => ({ error: new Error('systemctl missing') }) }), /systemctl missing/);
});

test('the scheduled night-light command finds Node without it being on PATH', t => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-night-service-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    const root = fileURLToPath(new URL('..', import.meta.url));
    const shim = path.join(home, '.local/share/mise/shims/node');
    fs.mkdirSync(path.dirname(shim), { recursive: true });
    fs.writeFileSync(shim, '#!/bin/sh\nexec "$INITD_NODE" "$@"\n', { mode: 0o755 });
    fs.mkdirSync(path.join(home, '.config'));
    fs.symlinkSync(path.join(root, 'linux/scripts/night-light-toggle.mjs'), path.join(home, '.config/night-light-toggle.mjs'));
    const bin = path.join(home, 'bin');
    fs.mkdirSync(bin);
    for (const [name, status] of [['systemctl', 3], ['pgrep', 1], ['qs', 0]]) {
        fs.writeFileSync(path.join(bin, name), `#!/bin/sh\nexit ${status}\n`, { mode: 0o755 });
    }
    const service = fs.readFileSync(path.join(root, 'linux/configs/systemd/user/night-light-schedule.service'), 'utf8');
    const [command, ...args] = service.match(/^ExecStart=(.+)$/m)[1].split(' ').map(arg => arg.replaceAll('%h', home));
    const result = spawnSync(command, args, {
        env: { ...process.env, HOME: home, PATH: bin, INITD_NODE: process.execPath, NIGHT_LIGHT_HOUR: '07' },
        encoding: 'utf8', timeout: 5000,
    });
    assert.equal(result.status, 0, result.stderr || result.error?.message);
});
