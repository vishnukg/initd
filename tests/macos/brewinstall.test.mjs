import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { main, parseArgs } from '../../macos/brewinstall.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));

function fixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-conversion-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const file = path.join(dir, 'Brewfile');
    fs.writeFileSync(file, '# curated', { mode: 0o640 });
    const calls = [];
    const commands = [];
    return { dir, file, calls, commands, log() {}, run(command, args) {
        commands.push(command);
        calls.push(args);
        return { status: args.includes('--cask') ? 1 : 0 };
    } };
}

for (const args of [[], ['--cask', '--formula', 'x'], ['a', 'b'], ['--bad'], ['x"'], ['#{system("bad")}'], ['x\ny'], ['-x']]) {
    test(`brewinstall rejects invalid arguments ${JSON.stringify(args)} before making changes`, t => {
        // Arrange
        const io = fixture(t);

        // Act: defer installation so assert.throws observes the rejection.
        const install = () => main(args, io);

        // Assert
        assert.throws(install);
        assert.deepEqual(io.calls, []);
        assert.deepEqual(io.commands, []);
        assert.equal(fs.readFileSync(io.file, 'utf8'), '# curated');
    });
}

test('brewinstall parses the brew alias and tapped versioned packages', () => {
    // Arrange
    const args = ['--brew', 'user/tap/tool@2'];

    // Act
    const parsed = parseArgs(args);

    // Assert
    assert.deepEqual(parsed, { kind: 'brew', name: 'user/tap/tool@2' });
});

test('brewinstall detects kind, preserves contents and mode, and retries without duplicating', t => {
    // Arrange
    const f = fixture(t);

    // Act
    main(['tool'], f);

    // Assert
    assert.equal(fs.readFileSync(f.file, 'utf8'), '# curated\nbrew "tool"\n');
    assert.equal(fs.statSync(f.file).mode & 0o777, 0o640);
    assert.deepEqual(f.calls.at(-1), ['bundle', '--file', f.file]);

    // Act
    main(['--formula', 'tool'], f);

    // Assert
    assert.equal(fs.readFileSync(f.file, 'utf8'), '# curated\nbrew "tool"\n');
    assert.deepEqual(fs.readdirSync(f.dir), ['Brewfile']);

    // Arrange
    fs.writeFileSync(f.file, '  brew "tool" # existing\ncask \'app\', greedy: true\n');

    // Act
    main(['tool'], f);
    main(['--cask', 'app'], { ...f, run: () => ({ status: 0 }) });

    // Assert
    assert.ok(f.commands.every(command => command === 'brew'));
    assert.equal(fs.readFileSync(f.file, 'utf8'), '  brew "tool" # existing\ncask \'app\', greedy: true\n');
});

for (const { name, args = ['tool'], result, expectedError } of [
    { name: 'ambiguous kind', result: { status: 0 }, expectedError: /both/ },
    { name: 'missing package', result: { status: 1 }, expectedError: /Cannot resolve/ },
    { name: 'missing cask', args: ['--cask', 'tool'], result: { status: 1 }, expectedError: /Cannot resolve/ },
    { name: 'missing executable', result: { error: new Error('ENOENT') }, expectedError: /ENOENT/ },
    { name: 'terminated lookup', result: { signal: 'SIGTERM' }, expectedError: /SIGTERM/ },
]) {
    test(`brewinstall leaves the file untouched after ${name}`, t => {
        // Arrange
        const io = fixture(t);
        const commands = [];
        const run = command => { commands.push(command); return result; };

        // Act: defer installation so assert.throws observes the failure.
        const install = () => main(args, { ...io, run });

        // Assert
        assert.throws(install, expectedError);
        assert.ok(commands.length > 0);
        assert.ok(commands.every(command => command === 'brew'));
        assert.equal(fs.readFileSync(io.file, 'utf8'), '# curated');
    });
}

test('brewinstall reports bundle failure and retains the entry for a retry', t => {
    // Arrange
    const f = fixture(t);

    // Act: define the operation whose error behavior is checked below
    const act = () => main(['--formula', 'tool'], { ...f, run: (_command, args) => ({ status: args[0] === 'bundle' ? 1 : 0 }) });

    // Assert
    assert.throws(act, /retained for retry/);
    assert.equal(fs.readFileSync(f.file, 'utf8'), '# curated\nbrew "tool"\n');
});

test('existing brewinstall command supports help and rejects invalid input without Homebrew', () => {
    // Arrange
    const command = path.join(root, 'macos/brewinstall');

    // Act
    const result = spawnSync(process.execPath, [command, '--help'], { encoding: 'utf8' });

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Usage: brewinstall/);

    // Act
    const bad = spawnSync(process.execPath, [command, 'bad"name'], { encoding: 'utf8' });

    // Assert
    assert.equal(bad.status, 1);
    assert.match(bad.stderr, /valid Homebrew package/);
});
