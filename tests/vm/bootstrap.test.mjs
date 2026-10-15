// The headless VM platform: which managed links it keeps, and the apt helpers
// of vm/bootstrap.sh, exercised by sourcing the production script and
// shadowing only the commands that would touch the machine. Nothing here needs
// Ubuntu, so it runs on any host.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { managedLinks } from '../../shared/lib/managed-links.mjs';

const root = path.resolve(fileURLToPath(new URL('../..', import.meta.url)));
const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-vm-'));
after(() => fs.rmSync(testRoot, { recursive: true, force: true }));

function newHome(name) {
    return fs.mkdtempSync(path.join(testRoot, `${name}-`));
}

// Every stub records its invocation; behaviour arrives as INITD_STUB_<name>.
const stubScript = path.join(testRoot, 'stub.sh');
fs.writeFileSync(stubScript, [
    '#!/bin/bash',
    'name="${0##*/}"',
    `printf '%s\\n' "$name $*" >> "$INITD_STUB_LOG"`,
    'behavior="INITD_STUB_${name//-/_}"',
    'eval "${!behavior:-}"',
    '',
].join('\n'), { mode: 0o755 });

function fixture() {
    const home = newHome('bootstrap');
    const bin = path.join(home, 'bin');
    const callLog = path.join(home, 'calls.log');
    const behaviors = {};
    fs.mkdirSync(bin);
    return {
        stub(name, body = '') {
            fs.symlinkSync(stubScript, path.join(bin, name));
            behaviors[`INITD_STUB_${name.replaceAll('-', '_')}`] = body;
        },
        calls() {
            return fs.existsSync(callLog) ? fs.readFileSync(callLog, 'utf8').trim().split('\n') : [];
        },
        run(code, env = {}) {
            return spawnSync('bash', ['-c', 'source "$1"\n' + code, 'fixture', path.join(root, 'vm/bootstrap.sh')], {
                env: {
                    ...process.env, HOME: home, BACKUP_ROOT: path.join(home, 'backup'), NO_COLOR: '1',
                    PATH: `${bin}:${process.env.PATH}`, INITD_STUB_LOG: callLog, ...behaviors, ...env,
                },
                encoding: 'utf8',
            });
        },
    };
}

function vmPackages() {
    return fs.readFileSync(path.join(root, 'vm/packages.txt'), 'utf8').split('\n')
        .map(line => line.replace(/#.*/, '').trim()).filter(Boolean);
}

test('vm links keep the shell and editor configs and drop the desktop ones', () => {
    // Arrange
    const home = newHome('links');

    // Act
    const homes = managedLinks(root, 'vm', home).map(entry => path.relative(home, entry.home));

    // Assert
    for (const kept of ['.gitconfig', '.config/fish', '.config/mise', '.config/nvim', '.config/starship.toml', '.config/tmux']) {
        assert.ok(homes.includes(kept), `missing ${kept}`);
    }
    for (const dropped of ['.config/kitty', '.config/ghostty', '.colima/_templates/default.yaml', '.local/share/wallpapers']) {
        assert.equal(homes.includes(dropped), false, `desktop link leaked: ${dropped}`);
    }
});

test('vm links point only into shared configs', () => {
    // Arrange
    const shared = path.join(root, 'shared') + path.sep;

    // Act
    const entries = managedLinks(root, 'vm', newHome('scope'));

    // Assert
    for (const entry of entries) assert.ok(entry.source.startsWith(shared), `out-of-scope link: ${entry.source}`);
});

test('link.mjs vm creates exactly the vm links', () => {
    // Arrange
    const home = newHome('install');

    // Act
    const result = spawnSync(process.execPath, [path.join(root, 'shared/lib/link.mjs'), 'vm'], {
        env: { ...process.env, HOME: home, BACKUP_ROOT: path.join(home, 'backup') }, encoding: 'utf8',
    });

    // Assert
    assert.equal(result.status, 0, result.stderr);
    for (const entry of managedLinks(root, 'vm', home)) assert.equal(fs.readlinkSync(entry.home), entry.source);
    assert.equal(fs.existsSync(path.join(home, '.config/kitty')), false);
});

test('install_packages installs only the missing packages, after one apt update', () => {
    // Arrange
    const packages = vmPackages();
    const installed = packages.filter(pkg => pkg !== 'tmux' && pkg !== 'ncurses-term');
    const env = fixture();
    env.stub('dpkg-query', `for p in ${installed.join(' ')}; do [[ "\${@: -1}" == "$p" ]] && printf 'install ok installed' && exit 0; done; exit 1`);
    env.stub('sudo', '"$@"');
    env.stub('apt-get');

    // Act
    const result = env.run('install_packages; apt_install extra');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    const apt = env.calls().filter(call => call.startsWith('apt-get '));
    assert.deepEqual(apt, [
        'apt-get update -q',
        'apt-get install -y -q --no-install-recommends tmux ncurses-term',
        'apt-get install -y -q --no-install-recommends extra',
    ]);
});

test('install_packages makes no apt calls when everything is installed', () => {
    // Arrange
    const env = fixture();
    env.stub('dpkg-query', `printf 'install ok installed'`);
    env.stub('sudo', '"$@"');
    env.stub('apt-get');

    // Act
    const result = env.run('install_packages');

    // Assert
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, new RegExp(`All ${vmPackages().length} apt packages already installed`));
    assert.equal(env.calls().some(call => call.startsWith('apt-get')), false);
});

test('ensure_fish_ppa keeps an installed fish 4 and replaces fish 3', () => {
    // Arrange
    const modern = fixture();
    modern.stub('fish', `echo 'fish, version 4.6.0'`);
    modern.stub('add-apt-repository');
    const legacy = fixture();
    legacy.stub('fish', `echo 'fish, version 3.7.0'`);
    legacy.stub('add-apt-repository');
    legacy.stub('sudo', '"$@"');
    legacy.stub('apt-get');

    // Act
    const kept = modern.run('ensure_fish_ppa');
    const replaced = legacy.run('ensure_fish_ppa');

    // Assert
    assert.equal(kept.status, 0, kept.stderr);
    assert.equal(modern.calls().some(call => call.startsWith('add-apt-repository')), false);
    assert.equal(replaced.status, 0, replaced.stderr);
    assert.ok(legacy.calls().includes('add-apt-repository -y ppa:fish-shell/release-4'));
    assert.ok(legacy.calls().includes('apt-get install -y -q --no-install-recommends fish'));
});
