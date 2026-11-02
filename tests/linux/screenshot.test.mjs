import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { screenshot, screenshotPath } from '../../linux/scripts/screenshot.mjs';

const now = new Date(2026, 0, 2, 3, 4, 5);

function fixture(t, results = {}) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-screenshot-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    const calls = [];
    const notices = [];
    const io = {
        run(command, args, options = {}) {
            calls.push({ command, args, stdinIsFd: typeof options.stdin === 'number' });
            // grim "writes" the file so wl-copy has something to open.
            if (command === 'grim' && !results.grim) fs.writeFileSync(args.at(-1), 'png');
            return results[command] ?? { status: 0, stdout: '', stderr: '' };
        },
        notify: message => notices.push(message),
    };
    return { home, calls, notices, io };
}

test('screenshot path is a local timestamp under ~/Pictures/Screenshots', () => {
    // Act
    const file = screenshotPath('/home/u', now);

    // Assert
    assert.equal(file, '/home/u/Pictures/Screenshots/screenshot-2026-01-02-03-04-05.png');
});

test('full screenshot creates ~/Pictures/Screenshots and captures every output without touching the clipboard', t => {
    // Arrange
    const f = fixture(t);

    // Act
    const file = screenshot('full', { home: f.home, now, io: f.io });

    // Assert
    assert.equal(file, path.join(f.home, 'Pictures/Screenshots/screenshot-2026-01-02-03-04-05.png'));
    assert.deepEqual(f.calls.map(c => [c.command, c.args]), [['grim', [file]]]);
    assert.deepEqual(f.notices, []);
});

test('region screenshot passes the slurp geometry to grim and pipes the file into wl-copy', t => {
    // Arrange
    const f = fixture(t, { slurp: { status: 0, stdout: '10,20 300x200\n', stderr: '' } });

    // Act
    const file = screenshot('region', { home: f.home, now, io: f.io });

    // Assert
    assert.deepEqual(f.calls.map(c => [c.command, c.args]), [
        ['slurp', []],
        ['grim', ['-g', '10,20 300x200', file]],
        ['wl-copy', ['--type', 'image/png']],
    ]);
    assert.equal(f.calls[2].stdinIsFd, true);
});

test('cancelling the region selection captures nothing and reports nothing', t => {
    // Arrange
    const f = fixture(t, { slurp: { status: 1, stdout: '', stderr: 'selection cancelled' } });

    // Act
    const result = screenshot('region', { home: f.home, now, io: f.io });

    // Assert
    assert.equal(result, null);
    assert.deepEqual(f.calls.map(c => c.command), ['slurp']);
    assert.deepEqual(f.notices, []);
});

test('a grim failure is surfaced as a notification, since the bind has no terminal', t => {
    // Arrange
    const f = fixture(t, { grim: { status: 1, stdout: '', stderr: 'compositor does not support screencopy\n' } });

    // Act
    const result = screenshot('full', { home: f.home, now, io: f.io });

    // Assert
    assert.equal(result, false);
    assert.deepEqual(f.notices, ['Failed: compositor does not support screencopy']);
});

test('an unknown mode is rejected before anything runs', t => {
    // Arrange
    const f = fixture(t);

    // Act / Assert
    assert.throws(() => screenshot('window', { home: f.home, now, io: f.io }), /Usage/);
    assert.deepEqual(f.calls, []);
});
