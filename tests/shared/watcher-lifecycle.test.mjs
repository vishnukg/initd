import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { claimWatcherLock, releaseWatcherLock, sweepCache, lockPath, watcherLockPath } from '../../shared/configs/tmux/.config/tmux/tmux.mjs';

const noTmux = spawnSync('tmux', ['-V']).status !== 0 && 'tmux is not installed';
const helper = fileURLToPath(new URL('../../shared/configs/tmux/.config/tmux/tmux.mjs', import.meta.url));

test('concurrent writers leave one complete cache value and no temporary files', { timeout: 5000 }, async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-agent-write-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'cache.json');
    const children = [];
    t.after(() => { for (const child of children) child.kill(); });

    // Act: run independent processes against the same atomic cache writer.
    await Promise.all(Array.from({ length: 8 }, (_, i) => new Promise((resolve, reject) => {
        const child = spawn(process.execPath, ['--input-type=module', '-e', 'import(process.env.INITD_AGENT_HELPER).then(m => m.atomic(process.env.INITD_TARGET, JSON.stringify({writer:process.env.INITD_WRITER,value:process.env.INITD_WRITER.repeat(10000)})))'], {
            env: { ...process.env, INITD_AGENT_HELPER: helper, INITD_TARGET: file, INITD_WRITER: String(i) },
            stdio: 'ignore',
        });
        children.push(child);
        child.on('error', reject);
        child.on('exit', code => code === 0 ? resolve() : reject(new Error(`writer exited ${code}`)));
    })));

    // Assert
    const record = JSON.parse(fs.readFileSync(file));
    assert.match(record.writer, /^[0-7]$/, 'the cache must contain a complete record from one writer');
    assert.equal(record.value, record.writer.repeat(10000), 'payload and writer must come from the same complete write');
    assert.deepEqual(fs.readdirSync(dir), ['cache.json']);
});

// The lock is addressed through an in-memory store rather than the real cache
// directory, so these never touch a running watcher's file.
function lockStore(initial = null) {
    let value = initial;
    return {
        get value() { return value; },
        io: (pid, alive = () => true) => ({
            pid,
            alive,
            create: next => {
                if (value !== null) throw Object.assign(new Error('EEXIST'), { code: 'EEXIST' });
                value = next;
            },
            read: () => {
                if (value === null) throw Object.assign(new Error('ENOENT'), { code: 'ENOENT' });
                return value;
            },
            write: next => { value = next; },
            remove: () => {
                if (value === null) throw Object.assign(new Error('ENOENT'), { code: 'ENOENT' });
                value = null;
            },
        }),
    };
}

test('exactly one watcher holds the lock while its holder stays alive', () => {
    // Arrange
    const store = lockStore();

    // Act
    const firstClaim = claimWatcherLock(1000, store.io(11));

    // Assert
    assert.equal(firstClaim, true, 'the first watcher takes it');

    // Act
    const claimByFollower = claimWatcherLock(1000, store.io(22));

    // Assert
    assert.equal(claimByFollower, false, 'a second client’s watcher idles');

    // Act
    const laterClaimByFollower = claimWatcherLock(1500, store.io(22));

    // Assert
    assert.equal(laterClaimByFollower, false);

    // Act
    // Ownership does not need a disk write every tick.
    const reclaimByHolder = claimWatcherLock(1500, store.io(11));

    // Assert
    assert.equal(reclaimByHolder, true);
    assert.equal(store.value, '11\n1000\n');
});

test('the lock passes on when its holder dies but never during slow live work', () => {
    // Arrange
    const dead = lockStore();

    // Act
    claimWatcherLock(1000, dead.io(11));
    // tmux SIGKILLs the job when a client goes away, so nothing is released.
    const claimAfterHolderDied = claimWatcherLock(1100, dead.io(22, pid => pid !== 11));

    // Assert
    assert.equal(claimAfterHolderDied, true, 'a dead holder must not block');
    assert.equal(dead.value, '22\n1100\n');

    // Arrange
    const stalled = lockStore();

    // Act
    claimWatcherLock(1000, stalled.io(11));
    const claimDuringSlowWork = claimWatcherLock(2500, stalled.io(22));

    // Assert
    assert.equal(claimDuringSlowWork, false);

    // Act
    const claimAfterLongSlowWork = claimWatcherLock(61000, stalled.io(22));

    // Assert
    assert.equal(claimAfterLongSlowWork, false, 'slow live work must retain ownership');
});

test('an unreadable lock is reclaimed rather than blocking the watcher forever', () => {
    // Arrange
    const store = lockStore('11\n');

    // Act
    // truncated: no heartbeat
    const claimOverTruncatedLock = claimWatcherLock(1000, store.io(22));

    // Assert
    assert.equal(claimOverTruncatedLock, true);
    assert.equal(store.value, '22\n1000\n');
});

test('a watcher releases only its own lock', () => {
    // Arrange
    const store = lockStore();

    // Act
    claimWatcherLock(1000, store.io(11));
    const releaseByFollower = releaseWatcherLock(store.io(22));

    // Assert
    assert.equal(releaseByFollower, false, 'a follower must not free the owner’s lock');
    assert.notEqual(store.value, null);

    // Act
    const releaseByHolder = releaseWatcherLock(store.io(11));

    // Assert
    assert.equal(releaseByHolder, true);
    assert.equal(store.value, null);

    // Act
    const releaseAgain = releaseWatcherLock(store.io(11));

    // Assert
    assert.equal(releaseAgain, false, 'releasing twice is a no-op');
});

test('the cache sweep deletes stale files while preserving locks and live owners', () => {
    // Arrange
    const names = ['watcher.lock', path.basename(lockPath), 'pane-1-2', 'pane-1-3',
        'pane-20-4', 'pane-30-5', 'claude-20.json', 'claude-30.json', 'writing.tmp', 'stray-file'];
    const deletions = [];

    // Act
    const removed = sweepCache('1', new Set(['2']), {
        readdir: () => names,
        remove: name => deletions.push(name),
        alive: pid => pid === 20,
    });

    // Assert
    const stale = ['pane-1-3', 'pane-30-5', 'claude-30.json', 'stray-file'];
    assert.deepEqual(removed, stale);
    assert.deepEqual(deletions, stale, 'locks, pending writes and live owners must survive');
});

test('separate tmux sockets elect independent owners and same-server followers idle', t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-watcher-locks-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));

    // Act
    const a = path.join(dir, path.basename(watcherLockPath('/tmp/tmux/default')));
    const b = path.join(dir, path.basename(watcherLockPath('/tmp/tmux/other')));

    // Arrange
    const owner = file => ({ path: file, pid: 11, alive: () => true });

    // Act
    const claimOnFirstSocket = claimWatcherLock(1000, owner(a));

    // Assert
    assert.equal(claimOnFirstSocket, true);

    // Act
    const claimOnSecondSocket = claimWatcherLock(1000, owner(b));

    // Assert
    assert.equal(claimOnSecondSocket, true);

    // Act
    const followerOnFirstSocket = claimWatcherLock(1000, { ...owner(a), pid: 22 });

    // Assert
    assert.equal(followerOnFirstSocket, false);

    // Act
    const releaseOfFirstSocket = releaseWatcherLock(owner(a));

    // Assert
    assert.equal(releaseOfFirstSocket, true);

    // Act
    const followerOnSecondSocket = claimWatcherLock(2000, { ...owner(b), pid: 22 });

    // Assert
    assert.equal(followerOnSecondSocket, false);
});

test('real watchers publish to both servers and a follower takes over after owner exit', {
    skip: noTmux || process.env.INITD_TEST_TMUX !== '1', timeout: 15000,
}, async t => {
    // Arrange
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-watchers-'));
    const sockets = [path.join(dir, 'a'), path.join(dir, 'b')];
    const children = [];
    t.after(async () => {
        await Promise.all(children.map(child => new Promise(resolve => {
            if (child.exitCode !== null || child.signalCode !== null) return resolve();
            child.once('exit', resolve);
            child.kill();
        })));
        for (const socket of sockets) {
            try { execFileSync('tmux', ['-S', socket, 'kill-server'], { stdio: 'ignore' }); } catch {}
        }
        fs.rmSync(dir, { recursive: true, force: true });
    });
    const waitUntil = async predicate => {
        const end = Date.now() + 5000;
        while (!predicate()) {
            if (Date.now() >= end) for (const socket of sockets) {
                t.diagnostic(execFileSync('tmux', ['-S', socket, 'list-panes', '-a', '-F', '#{pane_current_command}|#{@initd-agent}|#{pane_current_path}|#{@initd-directory}'], { encoding: 'utf8' }));
            }
            if (Date.now() >= end) throw new Error('watcher did not publish or hand over in time');
            await new Promise(resolve => setTimeout(resolve, 50));
        }
    };

    for (const socket of sockets) {
        execFileSync('tmux', ['-S', socket, '-f', '/dev/null', 'new-session', '-d', '-s', 'review', '/bin/sleep 30']);
    }

    // Arrange
    const socketPaths = new Map(sockets.map(socket => [socket,
        execFileSync('tmux', ['-S', socket, 'display-message', '-p', '#{socket_path}'], { encoding: 'utf8' }).trim()]));
    const start = socket => {
        const child = spawn(process.execPath, [helper, 'watch'], {
            env: { ...process.env, HOME: dir, TMUX: `${socket},1,0`, TMUX_PANE: undefined },
            stdio: ['ignore', 'ignore', 'pipe'],
        });
        child.stderr.resume();
        children.push(child);
        return child;
    };
    const lock = socket => path.join(dir, '.cache/initd-tmux', path.basename(watcherLockPath(socketPaths.get(socket))));
    const holder = socket => {
        try { return Number(fs.readFileSync(lock(socket), 'utf8').split('\n')[0]); } catch { return null; }
    };
    // Act: start one watcher per server and wait for the first publish.
    const owners = sockets.map(start);
    await waitUntil(() => sockets.every((socket, i) => holder(socket) === owners[i].pid));
    await waitUntil(() => sockets.every(socket => {
        try {
            const [current, published] = execFileSync('tmux', ['-S', socket, 'display-message', '-p', '-t', 'review', '#{pane_current_command}|#{@initd-agent}'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim().split('|');
            return !!current && current === published;
        }
        catch { return false; }
    }));

    // Act: a follower takes over when its own server's owner exits.
    const follower = start(sockets[0]);
    await new Promise(resolve => { owners[0].once('exit', resolve); owners[0].kill(); });
    await waitUntil(() => holder(sockets[0]) === follower.pid);

    // Act: change the pane's directory so the old owner's output cannot prove takeover.
    execFileSync('tmux', ['-S', sockets[0], 'respawn-pane', '-k', '-t', 'review', '-c', dir, '/bin/sleep 30']);
    await waitUntil(() => execFileSync('tmux', ['-S', sockets[0], 'display-message', '-p',
        '-t', 'review', '#{pane_current_path}|#{@initd-directory}'], { encoding: 'utf8' })
        .trim().split('|').every(value => value === fs.realpathSync(dir)));

    // Assert
    assert.equal(holder(sockets[0]), follower.pid, 'the follower owns the first server');
    assert.equal(holder(sockets[1]), owners[1].pid, 'another server keeps its owner');
});
