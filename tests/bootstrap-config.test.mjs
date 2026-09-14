// The config files bootstrap edits in place rather than owning outright, plus
// the Firefox profile glue. All four of these replaced embedded python3
// heredocs; the behaviour asserted here is the behaviour those had.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { readJsonFile, sameFlatObject, updateJsonFile } from '../shared/lib/json-file.mjs';
import { configureStatusLine } from '../shared/lib/claude-statusline.mjs';
import { configureDocker } from '../macos/docker-config.mjs';
import { profilePath, setDefaultZoom } from '../linux/scripts/firefox-profile.mjs';

const temporaryDir = t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-bootstrap-config-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    return dir;
};
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const mode = file => fs.statSync(file).mode & 0o777;

for (const [name, configure] of [['Claude', configureStatusLine], ['Docker', configureDocker]]) {
    for (const value of ['null', '[]', '42', '"text"']) {
        test(`${name} rejects non-object config ${value} without changing it`, t => {
            // Arrange
            const file = path.join(temporaryDir(t), 'config.json');
            fs.writeFileSync(file, value);

            // Act: defer configuration so assert.throws observes the rejection.
            const configureInvalidFile = () => configure({ file, log() {} });

            // Assert
            assert.throws(configureInvalidFile, /Expected a JSON object/);
            assert.equal(fs.readFileSync(file, 'utf8'), value);
        });
    }
}

for (const { name, contents } of [{ name: 'absent' }, { name: 'blank', contents: '   \n' }]) {
    test(`readJsonFile treats an ${name} config as empty`, t => {
        // Arrange
        const file = path.join(temporaryDir(t), 'config.json');
        if (contents !== undefined) fs.writeFileSync(file, contents);

        // Act
        const config = readJsonFile(file);

        // Assert
        assert.deepEqual(config, {});
    });
}

test('updateJsonFile creates a private config and its parent directory', t => {
    // Arrange
    const file = path.join(temporaryDir(t), 'nested', 'config.json');

    // Act
    const changed = updateJsonFile(file, config => { config.added = 1; return true; });

    // Assert
    assert.equal(changed, true);
    assert.deepEqual(read(file), { added: 1 });
    assert.equal(mode(file), 0o600);
    assert.match(fs.readFileSync(file, 'utf8'), /\n$/);
    assert.deepEqual(fs.readdirSync(path.dirname(file)), ['config.json']);
});

test('updateJsonFile preserves mtime when the config has not changed', t => {
    // Arrange
    const file = path.join(temporaryDir(t), 'config.json');
    fs.writeFileSync(file, '{"added":1}', { mode: 0o600 });
    const before = fs.statSync(file).mtimeMs;

    // Act
    const changed = updateJsonFile(file, () => false);

    // Assert
    assert.equal(changed, false);
    assert.equal(fs.statSync(file).mtimeMs, before);
});

test('updateJsonFile corrects permissive file permissions even without a content change', t => {
    // Arrange
    const file = path.join(temporaryDir(t), 'config.json');
    fs.writeFileSync(file, '{}');
    fs.chmodSync(file, 0o644);

    // Act
    updateJsonFile(file, () => false);

    // Assert
    assert.equal(mode(file), 0o600);
});

test('updateJsonFile merges changes without discarding unrelated keys or leaving temporary files', t => {
    // Arrange
    const file = path.join(temporaryDir(t), 'config.json');
    fs.writeFileSync(file, JSON.stringify({ added: 1, theirs: { deep: true } }));

    // Act
    updateJsonFile(file, config => { config.added = 2; return true; });

    // Assert
    assert.deepEqual(read(file), { added: 2, theirs: { deep: true } });
    assert.deepEqual(fs.readdirSync(path.dirname(file)), ['config.json']);
});

for (const [name, operation] of [
    ['readJsonFile', file => readJsonFile(file)],
    ['updateJsonFile', file => updateJsonFile(file, () => true)],
]) {
    test(`${name} rejects malformed JSON without changing the file`, t => {
        // Arrange
        const file = path.join(temporaryDir(t), 'config.json');
        fs.writeFileSync(file, '{"half":');

        // Act: defer the call so assert.throws observes the parser error.
        const readOrUpdate = () => operation(file);

        // Assert
        assert.throws(readOrUpdate, SyntaxError);
        assert.equal(fs.readFileSync(file, 'utf8'), '{"half":');
    });
}
for (const { name, left, right, expected } of [
    { name: 'key order is irrelevant', left: { a: 1, b: 2 }, right: { b: 2, a: 1 }, expected: true },
    { name: 'extra right key differs', left: { a: 1 }, right: { a: 1, b: 2 }, expected: false },
    { name: 'extra left key differs', left: { a: 1, b: 2 }, right: { a: 1 }, expected: false },
    { name: 'value types matter', left: { a: '1' }, right: { a: 1 }, expected: false },
    { name: 'inherited keys do not count', left: Object.assign(Object.create({ a: 1 }), { b: 2 }), right: { a: 1 }, expected: false },
    ...[undefined, null, 'x', 7, ['a']].map(left => ({ name: `non-object ${String(left)}`, left, right: { a: 1 }, expected: false })),
]) {
    test(`sameFlatObject: ${name}`, () => {
        // Arrange
        const objects = [left, right];

        // Act
        const equal = sameFlatObject(...objects);

        // Assert
        assert.equal(equal, expected);
    });
}
test('JSON updates preserve config symlinks and reject broken targets', t => {
    // Arrange
    const dir = temporaryDir(t);
    const target = path.join(dir, 'target.json');
    const link = path.join(dir, 'config.json');
    fs.writeFileSync(target, '{"theme":"dark"}');
    fs.symlinkSync('target.json', link);

    // Act
    configureStatusLine({ file: link, log() {} });

    // Assert
    assert.equal(fs.readlinkSync(link), 'target.json');
    assert.equal(read(target).theme, 'dark');
    assert.equal(read(target).statusLine.type, 'command');
    assert.equal(mode(target), 0o600);

    // Arrange
    fs.unlinkSync(target);

    // Act: define the operation whose error behavior is checked below
    const act = () => configureStatusLine({ file: link, log() {} });

    // Assert
    assert.throws(act, { code: 'ENOENT' });
    assert.equal(fs.readlinkSync(link), 'target.json');
    assert.equal(fs.existsSync(target), false);
});
test('the Claude statusLine hook is configured without disturbing other settings', t => {
    // Arrange
    const dir = temporaryDir(t);
    const file = path.join(dir, 'settings.json');
    const logged = [];
    const log = line => logged.push(line);

    // Act
    const configureStatusLineResult = configureStatusLine({ file, log });

    // Assert
    assert.equal(configureStatusLineResult, true);
    assert.deepEqual(read(file).statusLine, {
        type: 'command',
        command: '~/.config/tmux/claude-statusline-hook.mjs',
        refreshInterval: 60,
    });
    assert.match(logged.at(-1), /^OK .*configured/);

    // Act
    // Idempotent: a second run neither rewrites nor claims it did.
    const configureStatusLineResult2 = configureStatusLine({ file, log });

    // Assert
    assert.equal(configureStatusLineResult2, false);
    assert.match(logged.at(-1), /already configured/);

    // Arrange
    // The user's own Claude Code settings are not this repo's to touch.
    fs.writeFileSync(file, JSON.stringify({
        statusLine: { type: 'command', command: 'something-else' },
        model: 'opus', theme: 'auto', modelSettings: { 'claude-fable-5-1': { effortLevel: 'medium' } },
    }));

    // Act
    const configureStatusLineResult3 = configureStatusLine({ file, log });

    // Assert
    assert.equal(configureStatusLineResult3, true);
    const after = read(file);
    assert.equal(after.statusLine.command, '~/.config/tmux/claude-statusline-hook.mjs');
    assert.equal(after.model, 'opus');
    assert.equal(after.theme, 'auto');
    assert.deepEqual(after.modelSettings, { 'claude-fable-5-1': { effortLevel: 'medium' } });

    // Arrange
    // A key reshuffle by Claude Code is not a change worth a write.
    fs.writeFileSync(file, JSON.stringify({ statusLine: {
        refreshInterval: 60, command: '~/.config/tmux/claude-statusline-hook.mjs', type: 'command',
    } }));

    // Act
    const configureStatusLineResult4 = configureStatusLine({ file, log });

    // Assert
    assert.equal(configureStatusLineResult4, false);
});
test('Docker config gains the keychain helper and appends its plugin dir', t => {
    // Arrange
    const dir = temporaryDir(t);
    const file = path.join(dir, 'config.json');
    const log = () => {};
    const brewPlugins = '/opt/homebrew/lib/docker/cli-plugins';

    // Act
    const configureDockerResult = configureDocker({ file, log });

    // Assert
    assert.equal(configureDockerResult, true);
    assert.deepEqual(read(file), { credsStore: 'osxkeychain', cliPluginsExtraDirs: [brewPlugins] });
    // Can hold registry auth material even with a credential helper configured.
    assert.equal(mode(file), 0o600);

    // Act
    const configureDockerResult2 = configureDocker({ file, log });

    // Assert
    assert.equal(configureDockerResult2, false);

    // Arrange
    // Another install's plugin directory is appended to, never replaced, and
    // currentContext and auths are left alone.
    fs.writeFileSync(file, JSON.stringify({
        currentContext: 'colima',
        auths: { 'ghcr.io': {} },
        cliPluginsExtraDirs: ['/Users/me/.docker/cli-plugins'],
    }));

    // Act
    const configureDockerResult3 = configureDocker({ file, log });

    // Assert
    assert.equal(configureDockerResult3, true);
    assert.deepEqual(read(file), {
        currentContext: 'colima',
        auths: { 'ghcr.io': {} },
        cliPluginsExtraDirs: ['/Users/me/.docker/cli-plugins', brewPlugins],
        credsStore: 'osxkeychain',
    });

    // Act
    const configureDockerResult4 = configureDocker({ file, log });

    // Assert
    assert.equal(configureDockerResult4, false);

    // Arrange
    // A non-array value cannot be appended to, so it is normalised away rather
    // than crashing the bootstrap step.
    fs.writeFileSync(file, JSON.stringify({ credsStore: 'osxkeychain', cliPluginsExtraDirs: 'oops' }));

    // Act
    const configureDockerResult5 = configureDocker({ file, log });

    // Assert
    assert.equal(configureDockerResult5, true);
    assert.deepEqual(read(file).cliPluginsExtraDirs, [brewPlugins]);

    // Arrange
    // A different credential helper is corrected, not preserved.
    fs.writeFileSync(file, JSON.stringify({ credsStore: 'desktop', cliPluginsExtraDirs: [brewPlugins] }));

    // Act
    const configureDockerResult6 = configureDocker({ file, log });

    // Assert
    assert.equal(configureDockerResult6, true);
    assert.equal(read(file).credsStore, 'osxkeychain');
});
for (const { name, ini, expected } of [
    { name: 'per-install default wins over legacy default', ini: '[Profile1]\nName=old\nPath=abc.default\nDefault=1\n\n[Install4F96D1932A9F858E]\nDefault=xyz.default-release\nLocked=1\n', expected: 'xyz.default-release' },
    { name: 'legacy default works without an install section', ini: '[Profile0]\nPath=abc.default\nDefault=1\n', expected: 'abc.default' },
    { name: 'install section without default does not shadow legacy', ini: '[InstallABC]\nLocked=1\n\n[Profile0]\nPath=abc.default\nDefault=1\n', expected: 'abc.default' },
    { name: 'unmarked profile is not a default', ini: '[Profile0]\nPath=abc.default\n', expected: null },
    { name: 'empty registry has no default', ini: '', expected: null },
    { name: 'comments, whitespace and absolute paths are supported', ini: '; a comment\n# another\n[InstallX]\n  default = /abs/profile  \n', expected: '/abs/profile' },
    { name: 'legacy keys are case insensitive', ini: '[Profile0]\npath=abc\ndefault=1\n', expected: 'abc' },
    { name: 'keys outside sections are ignored', ini: 'Default=stray\n[InstallX]\nDefault=real\n', expected: 'real' },
]) {
    test(`Firefox profilePath: ${name}`, () => {
        // Arrange
        const registry = ini;

        // Act
        const profile = profilePath(registry);

        // Assert
        assert.equal(profile, expected);
    });
}
test('the Firefox default zoom is set globally without touching per-site levels', t => {
    // Arrange
    const dir = temporaryDir(t);
    const file = path.join(dir, 'content-prefs.sqlite');
    const build = () => {
        const db = new DatabaseSync(file);
        db.exec('create table settings (id integer primary key, name text)');
        db.exec(`create table prefs (id integer primary key, groupID integer,
            settingID integer, value real, timestamp integer)`);
        return db;
    };
    let db = build();
    db.exec("insert into settings (name) values ('browser.download.dir')");
    db.close();

    // Act
    setDefaultZoom(file, { now: 1_700_000_000_000 });

    // Assert
    db = new DatabaseSync(file);
    // Spread because node:sqlite hands back null-prototype rows, which strict
    // deep equality will not match against a plain object literal.
    const globals = () => db.prepare(`select p.value, p.timestamp from prefs p
        join settings s on s.id = p.settingID
        where p.groupID is null and s.name = 'browser.content.full-zoom'`).all().map(row => ({ ...row }));

    assert.deepEqual(globals(), [{ value: 1.33, timestamp: 1_700_000_000 }]);
    // The setting row was added rather than replacing the unrelated one.
    assert.equal(db.prepare('select count(*) as n from settings').get().n, 2);
    const settingId = db.prepare("select id from settings where name = 'browser.content.full-zoom'").get().id;

    // Arrange
    // A per-site level (groupID set) belongs to the user and must survive.
    db.prepare('insert into prefs (groupID, settingID, value, timestamp) values (?, ?, ?, ?)')
        .run(7, settingId, 2.0, 1);
    // A stale duplicate global is replaced, not added to, so id order cannot
    // leave the old value winning.
    db.prepare('insert into prefs (groupID, settingID, value, timestamp) values (NULL, ?, ?, ?)')
        .run(settingId, 0.5, 2);
    db.close();

    // Act
    setDefaultZoom(file, { zoom: 1.5, now: 1_700_000_001_000 });

    // Assert
    db = new DatabaseSync(file);

    assert.deepEqual(globals(), [{ value: 1.5, timestamp: 1_700_000_001 }]);
    assert.deepEqual(db.prepare('select groupID, value from prefs where groupID is not null').all()
        .map(row => ({ ...row })), [{ groupID: 7, value: 2.0 }]);
    // Re-running reuses the existing settings row rather than piling up more.
    assert.equal(db.prepare('select count(*) as n from settings').get().n, 2);

    db.close();
});
