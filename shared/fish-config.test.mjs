import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fish = execFileSync('which', ['fish'], { encoding: 'utf8' }).trim();
const source = path.join(__dirname, 'configs/fish/.config/fish/config.fish');
const plain = value => value.replace(/\x1b\[[0-9;]* q/g, '').trim();
function fixture(t) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-fish-test-'));
    t.after(() => fs.rmSync(root, { recursive: true, force: true }));
    const config = path.join(root, 'config/fish');
    const bin = path.join(root, 'bin');
    fs.mkdirSync(config, { recursive: true });
    fs.mkdirSync(bin);
    fs.copyFileSync(source, path.join(config, 'config.fish'));
    fs.writeFileSync(path.join(config, 'local.env.fish'), `set -gx PATH '${bin}' /usr/bin /bin\nset -gx INITD_TEST_WORK work\n`);
    fs.writeFileSync(path.join(config, 'local.fish'), 'set -g INITD_TEST_INTERACTIVE yes\n');
    for (const tool of ['zoxide', 'starship', 'mise']) {
        fs.writeFileSync(path.join(bin, tool), `#!${process.execPath}\nconsole.log('set -g __initd_seen_${tool} '+(process.env.INITD_TEST_VERSION || 'one')); process.exit(process.env.INITD_TEST_FAIL ? 1 : 0);\n`, { mode: 0o755 });
    }
    const env = { ...process.env, HOME: root, XDG_CONFIG_HOME: path.join(root, 'config'), XDG_CACHE_HOME: path.join(root, 'cache'), TMUX: 'fixture', TERM: 'xterm-256color', MISE_FISH_AUTO_ACTIVATE: '0' };
    return { root, env, bin, run: (code, interactive = true, extra = {}) => plain(execFileSync(fish, [...(interactive ? ['-i'] : []), '-c', code], { env: { ...env, ...extra }, encoding: 'utf8' })) };
}
function cachedToolInit(shell) {
    // Fish may create its own cache directory; only persisted tool init is a
    // regression. The marker comes from the fake generators in fixture().
    return [shell.env.XDG_CACHE_HOME, path.join(shell.root, '.cache')].flatMap(directory => {
        if (!fs.existsSync(directory)) return [];
        return fs.readdirSync(directory, { recursive: true }).map(file => path.join(directory, file))
            .filter(file => fs.statSync(file).isFile() && fs.readFileSync(file, 'utf8').includes('__initd_seen_'));
    });
}
test('Fish config parses and noninteractive shells load only environment overrides', t => {
    // Arrange
    const shell = fixture(t);

    // Act
    const syntaxOutput = execFileSync(fish, ['-n', source], { encoding: 'utf8' });
    const noninteractive = shell.run('echo $INITD_TEST_WORK; set -q INITD_TEST_INTERACTIVE; and echo bad; true', false);
    const interactive = shell.run('echo $INITD_TEST_WORK $INITD_TEST_INTERACTIVE');

    // Assert
    assert.equal(syntaxOutput, '');
    assert.equal(noninteractive, 'work');
    assert.equal(interactive, 'work yes');
});
test('tool init is fresh, rejects failed output, and defers mise until preexec', t => {
    // Arrange
    const shell = fixture(t);

    // Act
    const initialized = shell.run('echo $__initd_seen_starship $__initd_seen_zoxide; set -q __initd_seen_mise; and echo early; emit fish_preexec; echo $__initd_seen_mise');
    const updated = shell.run('echo $__initd_seen_starship', true, { INITD_TEST_VERSION: 'two' });
    const failed = shell.run('set -q __initd_seen_starship; and echo bad; true', true, { INITD_TEST_FAIL: '1' });

    // Assert
    assert.equal(initialized, 'one one\none');
    assert.equal(updated, 'two');
    assert.equal(failed, '');
    assert.deepEqual(cachedToolInit(shell), []);
});
test('concurrent Fish startups have independent init and do not write a shared cache', async t => {
    // Arrange
    const f = fixture(t);

    // Act
    const values = await Promise.all(Array.from({ length: 6 }, (_, i) => new Promise((resolve, reject) => {
        const child = spawn(fish, ['-i', '-c', 'echo $__initd_seen_starship'], { env: { ...f.env, INITD_TEST_VERSION: String(i) } });
        let output = '';
        child.stdout.on('data', data => { output += data; });
        child.on('error', reject);
        child.on('close', code => code === 0 ? resolve(plain(output)) : reject(new Error(`Fish exited ${code}`)));
    })));

    // Assert
    assert.deepEqual(values, ['0', '1', '2', '3', '4', '5']);
    assert.deepEqual(cachedToolInit(f), []);
});
test('non-TTY interactive shells never attempt tmux auto-attach', t => {
    // Arrange
    const f = fixture(t);
    fs.writeFileSync(path.join(f.bin, 'tmux'), '#!/bin/sh\necho unexpected-tmux\nexit 1\n', { mode: 0o755 });

    // Act
    const frunResult = f.run('echo ready', true, { TMUX: undefined });

    // Assert
    assert.equal(frunResult, 'ready');
});
test('tmux server-side selection gives concurrent clients separate sessions', { skip: process.env.INITD_TEST_TMUX !== '1', timeout: 15000 }, async t => {
    // Arrange
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-fish-tmux-'));
    const socket = path.join(root, 'socket');
    const clients = [];
    t.after(() => {
        for (const child of clients) child.kill();
        try { execFileSync('tmux', ['-S', socket, 'kill-server'], { stdio: 'ignore' }); } catch {}
        fs.rmSync(root, { recursive: true, force: true });
    });

    execFileSync('tmux', ['-S', socket, '-f', '/dev/null', 'new-session', '-d', '-s', 'existing', '/bin/sh']);

    const branch = fs.readFileSync(source, 'utf8').match(/command tmux start-server \\; if-shell -F '([^']+)' '([^']+)' '([^']+)'/);

    if (!branch) throw new Error('Fish config has no tmux selection command to exercise');

    // Act
    await Promise.all(Array.from({ length: 6 }, () => new Promise((resolve, reject) => {
        const child = spawn('tmux', ['-C', '-S', socket, 'start-server', ';', 'if-shell', '-F', ...branch.slice(1)], { env: { ...process.env, SHELL: '/bin/sh' } });
        clients.push(child);
        let output = '';
        child.stdout.on('data', data => {
            output += data;
            if (output.includes('%session-changed ')) resolve();
        });
        child.on('error', reject);
        child.on('exit', code => reject(new Error(`tmux exited ${code}: ${output}`)));
    })));

    const sessions = execFileSync('tmux', ['-S', socket, 'list-sessions', '-F', '#{session_name}:#{session_attached}'], { encoding: 'utf8' }).trim().split('\n');

    // Assert
    assert.equal(sessions.length, 6);
    assert.ok(sessions.includes('existing:1'));
    assert.ok(sessions.every(s => s.endsWith(':1')));
});
// A pty is the whole point here: `exit` from a sourced config.fish stops the
// sourcing but leaves an interactive shell at a prompt, and only a real
// terminal shows that. A tmux pane is the pty this suite already depends on.
function ptyShell(t, tmuxScript) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-fish-pty-'));
    const socket = path.join(os.tmpdir(), `ifp-${process.pid}-${Math.random().toString(36).slice(2, 8)}`);
    t.after(() => {
        try { execFileSync('tmux', ['-S', socket, 'kill-server'], { stdio: 'ignore' }); } catch {}
        fs.rmSync(root, { recursive: true, force: true });
    });
    const config = path.join(root, 'config/fish');
    const bin = path.join(root, 'bin');
    fs.mkdirSync(config, { recursive: true });
    fs.mkdirSync(bin);
    fs.copyFileSync(source, path.join(config, 'config.fish'));
    fs.writeFileSync(path.join(config, 'local.env.fish'), `set -gx PATH '${bin}' /usr/bin /bin\n`);
    fs.writeFileSync(path.join(bin, 'tmux'), tmuxScript, { mode: 0o755 });
    execFileSync('tmux', ['-S', socket, '-f', '/dev/null', 'new-session', '-d', '-s', 'pty',
        // -u TMUX: the pane is itself inside tmux, and the block under test is
        // skipped whenever TMUX is already set.
        `env -u TMUX -u TMUX_PANE HOME=${root} XDG_CONFIG_HOME=${path.join(root, 'config')} MISE_FISH_AUTO_ACTIVATE=0 ${fish} -i`]);
    return {
        tmuxWasInvoked: () => fs.existsSync(path.join(root, 'tmux-invoked')),
        commandFinished: () => fs.existsSync(path.join(root, 'shell-ready')),
        send: command => execFileSync('tmux', ['-S', socket, 'send-keys', '-t', 'pty', command, 'Enter']),
        alive: () => {
            try {
                execFileSync('tmux', ['-S', socket, 'has-session', '-t', 'pty'], { stdio: 'ignore' });
                return true;
            } catch { return false; }
        },
        screen: () => plain(execFileSync('tmux', ['-S', socket, 'capture-pane', '-p', '-t', 'pty'], { encoding: 'utf8' })),
    };
}
async function waitUntil(predicate, description) {
    const deadline = performance.now() + 5000;
    while (!predicate()) {
        if (performance.now() >= deadline) throw new Error(`Timed out waiting for ${description}`);
        await delay(25);
    }
}
test('the shell closes the terminal when tmux exits cleanly', { skip: process.env.INITD_TEST_TMUX !== '1', timeout: 15000 }, async t => {
    // Arrange
    const tmuxScript = '#!/bin/sh\n: > "$HOME/tmux-invoked"\nexit 0\n';

    // Act: launch Fish in a real terminal and let auto-attach finish.
    const shell = ptyShell(t, tmuxScript);
    await waitUntil(() => shell.tmuxWasInvoked() && !shell.alive(), 'Fish to exit after tmux');

    // Assert
    assert.equal(shell.tmuxWasInvoked(), true, 'the shell must exercise auto-attach before exiting');
    assert.equal(shell.alive(), false, 'killing the last tmux window must close the terminal, not drop to Fish');
});
test('a failed tmux leaves a usable shell rather than closing the terminal', { skip: process.env.INITD_TEST_TMUX !== '1', timeout: 15000 }, async t => {
    // Arrange
    const tmuxScript = '#!/bin/sh\n: > "$HOME/tmux-invoked"\nexit 1\n';

    // Act: launch Fish in a real terminal and let auto-attach fail.
    const shell = ptyShell(t, tmuxScript);
    await waitUntil(() => shell.tmuxWasInvoked() && shell.alive()
        && /could not attach/.test(shell.screen()), 'the attach failure message');
    shell.send('printf ready > "$HOME/shell-ready"');
    await waitUntil(shell.commandFinished, 'Fish to execute a command after the attach failure');

    // Assert
    assert.equal(shell.alive(), true, 'a shell that cannot reach tmux must stay usable');
    assert.equal(shell.commandFinished(), true, 'the surviving shell must execute commands');
    assert.match(shell.screen(), /could not attach/);
});
