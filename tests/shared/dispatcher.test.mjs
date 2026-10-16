// bootstrap.sh picks the platform bootstrap: the one named on the command
// line, or the OS default when none is. The real dispatcher runs in a scratch
// root whose platform scripts only record that they ran, with uname stubbed,
// so every platform can be exercised from any host.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));

function fixture(t, uname) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-dispatch-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const bin = path.join(dir, 'bin');
    fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin, 'uname'), `#!/bin/sh\necho ${uname}\n`, { mode: 0o755 });
    fs.copyFileSync(path.join(root, 'bootstrap.sh'), path.join(dir, 'bootstrap.sh'));
    for (const platform of ['macos', 'linux', 'vm']) {
        fs.mkdirSync(path.join(dir, platform));
        fs.writeFileSync(path.join(dir, platform, 'bootstrap.sh'),
            `#!/bin/sh\necho "ran ${platform} $#"\n`, { mode: 0o755 });
    }
    return (...args) => spawnSync('bash', [path.join(dir, 'bootstrap.sh'), ...args], {
        env: { PATH: `${bin}:/usr/bin:/bin` }, encoding: 'utf8', timeout: 10000,
    });
}

for (const [uname, args, expected] of [
    ['Darwin', [], 'macos'],
    ['Linux', [], 'linux'],
    ['Darwin', ['macos'], 'macos'],
    ['Darwin', ['mac'], 'macos'],
    ['Linux', ['linux'], 'linux'],
    ['Linux', ['vm'], 'vm'],
]) {
    test(`${uname} with ${args.length ? `"${args[0]}"` : 'no platform'} runs the ${expected} bootstrap`, t => {
        // Arrange
        const run = fixture(t, uname);

        // Act
        const result = run(...args);

        // Assert: and the platform name is not passed on to it.
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout.trim(), `ran ${expected} 0`);
    });
}

for (const [uname, platform, message] of [
    ['Linux', 'macos', /'macos' needs Darwin, but this machine is Linux/],
    ['Darwin', 'vm', /'vm' needs Linux, but this machine is Darwin/],
    ['Darwin', 'linux', /'linux' needs Linux, but this machine is Darwin/],
]) {
    test(`"${platform}" on ${uname} is refused before anything runs`, t => {
        // Arrange
        const run = fixture(t, uname);

        // Act
        const result = run(platform);

        // Assert
        assert.equal(result.status, 1);
        assert.equal(result.stdout, '');
        assert.match(result.stderr, message);
    });
}

test('an unknown platform prints the usage and fails', t => {
    // Arrange
    const run = fixture(t, 'Darwin');

    // Act
    const result = run('windows');

    // Assert
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /Unknown platform: windows/);
    assert.match(result.stderr, /Usage: bootstrap\.sh \[macos\|linux\|vm\]/);
});

test('an unsupported OS with no platform fails', t => {
    // Arrange
    const run = fixture(t, 'FreeBSD');

    // Act
    const result = run();

    // Assert
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Unsupported OS: FreeBSD/);
});

test('--help prints the usage and runs nothing', t => {
    // Arrange
    const run = fixture(t, 'Darwin');

    // Act
    const result = run('--help');

    // Assert
    assert.equal(result.status, 0);
    assert.match(result.stdout, /Usage: bootstrap\.sh \[macos\|linux\|vm\]/);
    assert.doesNotMatch(result.stdout, /^ran /m);
});
