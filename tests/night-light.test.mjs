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
    const delays = [];
    return {
        calls,
        delays,
        get waits() { return delays.length; },
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
            delays.push(milliseconds);
            if (!stuck) stray = false;
        },
    };
}

for (const [hour, expected] of [[0, 'on'], [6, 'on'], [19, 'on'], [23, 'on'], [7, 'off'], [12, 'off'], [18, 'off']]) {
    test(`night-light schedule at hour ${hour} is ${expected}`, () => {
        // Arrange
        const requestedHour = hour;

        // Act
        const state = scheduledState(requestedHour);

        // Assert
        assert.equal(state, expected);
    });
}
for (const hour of [-1, 24, 1.5, NaN]) {
    test(`night-light schedule rejects hour ${hour}`, () => {
        // Arrange
        const requestedHour = hour;

        // Act: defer the call so assert.throws can observe the error.
        const schedule = () => scheduledState(requestedHour);

        // Assert
        assert.throws(schedule, /between 0 and 23/);
    });
}

test('night-light on/off are idempotent and toggle follows service state', async () => {
    // Arrange
    const io = fixture();

    // Act
    await nightLight(['on'], io);
    await nightLight(['on'], io);
    await nightLight([], io);
    await nightLight(['off'], io);

    // Assert
    assert.equal(io.calls.filter(call => call[0] === 'systemctl' && call[2] === 'start').length, 1);
    assert.equal(io.calls.filter(call => call[0] === 'systemctl' && call[2] === 'stop').length, 1);
    assert.deepEqual(io.calls.filter(call => call[0] === 'notify-send').map(call => call.at(-1)), ['On (4500K)', 'Off']);
    assert.equal(io.calls.filter(call => call[0] === 'qs').length, 4);
});

test('night-light auto applies the requested hour', async () => {
    // Arrange
    const io = fixture();

    // Act
    await nightLight(['auto'], { ...io, hour: 19 });
    await nightLight(['auto'], { ...io, hour: 7 });

    // Assert
    assert.deepEqual(io.calls.filter(call => call[0] === 'notify-send').map(call => call.at(-1)), ['On (4500K)', 'Off']);
});

test('night-light waits for stray gamma controllers before starting', async () => {
    // Arrange
    const io = fixture({ stray: true });

    // Act
    await nightLight(['on'], io);

    // Assert
    assert.deepEqual(io.delays, [100]);
    const stopStray = io.calls.findIndex(call => call[0] === 'pkill');
    const startService = io.calls.findIndex(call => call[0] === 'systemctl' && call[2] === 'start');
    assert.ok(stopStray >= 0, 'the stray gamma controller must be stopped');
    assert.ok(startService > stopStray, 'the service must start after stopping the stray controller');
});

test('a stuck gamma controller prevents a second start and still refreshes the bar', async () => {
    // Arrange
    const io = fixture({ stray: true, stuck: true });

    // Act
    const operation = nightLight(['on'], io);

    // Assert
    await assert.rejects(operation, /refusing to start/);
    assert.equal(io.waits, 80);
    assert.ok(io.delays.every(milliseconds => milliseconds === 100));
    assert.ok(!io.calls.some(call => call[0] === 'systemctl' && call[2] === 'start'));
    assert.ok(!io.calls.some(call => call[0] === 'notify-send'));
    assert.equal(io.calls.at(-1)[0], 'qs');
});

test('a skipped night-light service never announces success', async () => {
    // Arrange
    const io = fixture({ skipStart: true });

    // Act
    await nightLight(['on'], io);

    // Assert
    assert.ok(!io.calls.some(call => call[0] === 'notify-send'));
});

test('a failed night-light stop refreshes the bar without announcing success', async () => {
    // Arrange
    const io = fixture({ active: true, failStop: true });

    // Act
    const stopping = nightLight(['off'], io);

    // Assert
    await assert.rejects(stopping, /systemctl failed/);
    assert.ok(!io.calls.some(call => call[0] === 'notify-send'));
    assert.equal(io.calls.at(-1)[0], 'qs');
});

for (const args of [['bad'], ['on', 'off']]) {
    test(`night-light rejects invalid arguments: ${args.join(' ')}`, async () => {
        // Arrange
        const io = fixture();

        // Act
        const operation = nightLight(args, io);

        // Assert
        await assert.rejects(operation, /Usage:/);
        assert.deepEqual(io.calls, []);
    });
}

test('night-light tolerates missing optional notification and bar tools', async () => {
    // Arrange
    const io = fixture();
    const optionalToolsMissing = { ...io, run(command, args) {
        if (['notify-send', 'qs'].includes(command)) return { error: new Error('missing') };
        return io.run(command, args);
    } };

    // Act
    const operation = nightLight(['on'], optionalToolsMissing);

    // Assert
    await assert.doesNotReject(operation);
    assert.ok(io.calls.some(call => call[0] === 'systemctl' && call[2] === 'start'));
});

test('night-light reports a missing systemctl executable', async () => {
    // Arrange
    const io = { run: () => ({ error: new Error('systemctl missing') }) };

    // Act
    const operation = nightLight(['on'], io);

    // Assert
    await assert.rejects(operation, /systemctl missing/);
});

test('the scheduled night-light command finds Node without it being on PATH', t => {
    // Arrange
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

    // Act
    const result = spawnSync(command, args, {
        env: { ...process.env, HOME: home, PATH: bin, INITD_NODE: process.execPath, NIGHT_LIGHT_HOUR: '07' },
        encoding: 'utf8', timeout: 5000,
    });

    // Assert
    assert.equal(result.status, 0, result.stderr || result.error?.message);
});
