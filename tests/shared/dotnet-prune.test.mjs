// shared/lib/dotnet-prune.mjs: removes what mise leaves behind in its shared
// .NET root after an SDK is uninstalled or upgraded.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { pruneDotnetRoot } from '../../shared/lib/dotnet-prune.mjs';

const script = fileURLToPath(new URL('../../shared/lib/dotnet-prune.mjs', import.meta.url));
const versionedDirectories = [
    'shared/Microsoft.NETCore.App', 'shared/Microsoft.AspNetCore.App',
    'packs/Microsoft.NETCore.App.Ref', 'packs/Microsoft.NETCore.App.Host.linux-x64',
    'host/fxr', 'templates',
];

// A dotnet root shaped like mise's: SDKs in sdk/<version>, each naming its
// runtime, and every runtime version present in each versioned directory.
function dotnetRoot(t, { sdks, runtimes, bands = ['10.0.100'] }) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-dotnet-'));
    t.after(() => fs.rmSync(root, { recursive: true, force: true }));
    for (const [sdk, runtime] of Object.entries(sdks)) {
        fs.mkdirSync(path.join(root, 'sdk', sdk), { recursive: true });
        if (runtime) {
            fs.writeFileSync(path.join(root, 'sdk', sdk, 'dotnet.runtimeconfig.json'),
                JSON.stringify({ runtimeOptions: { framework: { name: 'Microsoft.NETCore.App', version: runtime } } }));
        }
    }
    for (const directory of versionedDirectories) {
        for (const runtime of runtimes) {
            fs.mkdirSync(path.join(root, directory, runtime), { recursive: true });
            fs.writeFileSync(path.join(root, directory, runtime, 'payload'), 'x');
        }
    }
    for (const band of bands) fs.mkdirSync(path.join(root, 'sdk-manifests', band), { recursive: true });
    return root;
}

function present(root, directory) {
    return fs.readdirSync(path.join(root, directory)).sort();
}

test('keeps only the runtime each SDK uses, in every versioned directory', t => {
    // Arrange: .NET 8 was uninstalled (its SDK is gone) and 10 had patch upgrades.
    const root = dotnetRoot(t, {
        sdks: { '10.0.403': '10.0.14' },
        runtimes: ['8.0.32', '8.0.33', '10.0.12', '10.0.13', '10.0.14'],
        bands: ['8.0.100', '10.0.100'],
    });

    // Act
    const removed = pruneDotnetRoot(root);

    // Assert
    for (const directory of versionedDirectories) assert.deepEqual(present(root, directory), ['10.0.14'], directory);
    assert.deepEqual(present(root, 'sdk'), ['10.0.403']);
    assert.deepEqual(present(root, 'sdk-manifests'), ['10.0.100']);
    assert.equal(removed.length, versionedDirectories.length * 4 + 1);
});

test('two installed SDKs keep both their runtimes', t => {
    // Arrange: dotnet = ["lts", "8"] style, both SDKs still installed.
    const root = dotnetRoot(t, {
        sdks: { '8.0.427': '8.0.33', '10.0.403': '10.0.14' },
        runtimes: ['8.0.32', '8.0.33', '10.0.14'],
        bands: ['8.0.100', '10.0.100'],
    });

    // Act
    pruneDotnetRoot(root);

    // Assert
    for (const directory of versionedDirectories) assert.deepEqual(present(root, directory), ['10.0.14', '8.0.33'], directory);
    assert.deepEqual(present(root, 'sdk-manifests'), ['10.0.100', '8.0.100']);
});

test('always keeps the newest version in a directory, even one no SDK names', t => {
    // Arrange: the SDK names a runtime that is not on disk (a layout misread).
    const root = dotnetRoot(t, { sdks: { '10.0.403': '10.0.99' }, runtimes: ['10.0.13', '10.0.14'] });

    // Act
    pruneDotnetRoot(root);

    // Assert
    for (const directory of versionedDirectories) assert.deepEqual(present(root, directory), ['10.0.14'], directory);
});

test('a release outranks its own previews when picking the newest', t => {
    // Arrange
    const root = dotnetRoot(t, {
        sdks: { '10.0.403': '10.0.99' },
        runtimes: ['11.0.0-rc.2.26504.105', '11.0.0', '11.0.0-rc.10.1'],
    });

    // Act
    pruneDotnetRoot(root);

    // Assert
    assert.deepEqual(present(root, 'host/fxr'), ['11.0.0']);
});

test('touches nothing when an SDK runtime cannot be read', t => {
    // Arrange: one SDK has no runtimeconfig, so "unused" cannot be measured.
    const root = dotnetRoot(t, {
        sdks: { '8.0.427': undefined, '10.0.403': '10.0.14' },
        runtimes: ['8.0.33', '10.0.14'],
    });

    // Act
    const removed = pruneDotnetRoot(root);

    // Assert
    assert.deepEqual(removed, []);
    assert.deepEqual(present(root, 'host/fxr'), ['10.0.14', '8.0.33']);
});

test('touches nothing when no SDK is installed', t => {
    // Arrange
    const root = dotnetRoot(t, { sdks: {}, runtimes: ['8.0.33', '10.0.14'] });

    // Act
    const removed = pruneDotnetRoot(root);

    // Assert
    assert.deepEqual(removed, []);
    assert.deepEqual(present(root, 'host/fxr'), ['10.0.14', '8.0.33']);
});

test('--dry-run reports without removing, and a second real run finds nothing', t => {
    // Arrange
    const root = dotnetRoot(t, { sdks: { '10.0.403': '10.0.14' }, runtimes: ['8.0.33', '10.0.14'] });
    const run = (...args) => spawnSync(process.execPath, [script, ...args, root], { encoding: 'utf8' });

    // Act
    const dry = run('--dry-run');
    const afterDry = present(root, 'host/fxr');
    const real = run();
    const again = run();

    // Assert
    assert.equal(dry.status, 0, dry.stderr);
    assert.match(dry.stdout, /would remove host\/fxr\/8\.0\.33/);
    assert.deepEqual(afterDry, ['10.0.14', '8.0.33']);
    assert.equal(real.status, 0, real.stderr);
    assert.match(real.stdout, /^OK Removed 6 unused \.NET directories/m);
    assert.deepEqual(present(root, 'host/fxr'), ['10.0.14']);
    assert.match(again.stdout, /^OK \.NET root holds only what its SDKs use\.$/m);
});
