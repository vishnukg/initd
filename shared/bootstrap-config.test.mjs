// The config files bootstrap edits in place rather than owning outright, plus
// the Firefox profile glue. All four of these replaced embedded python3
// heredocs; the behaviour asserted here is the behaviour those had.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { readJsonFile, sameFlatObject, updateJsonFile } from './lib/json-file.mjs';
import { configureStatusLine } from './lib/claude-statusline.mjs';
import { configureDocker } from '../macos/docker-config.mjs';
import { profilePath, setDefaultZoom } from '../linux/scripts/firefox-profile.mjs';

const temporaryDir = t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-bootstrap-config-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    return dir;
};
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const mode = file => fs.statSync(file).mode & 0o777;

test('non-object JSON configs are rejected without changing their contents', t => {
    const file = path.join(temporaryDir(t), 'config.json');
    for (const value of ['null', '[]', '42', '"text"']) {
        fs.writeFileSync(file, value);
        assert.throws(() => configureStatusLine({ file, log() {} }), /Expected a JSON object/);
        assert.throws(() => configureDocker({ file, log() {} }), /Expected a JSON object/);
        assert.equal(fs.readFileSync(file, 'utf8'), value);
    }
});

test('a JSON config is merged in place, written only on change, and kept private', t => {
    const dir = temporaryDir(t);
    const file = path.join(dir, 'nested', 'config.json');
    // An absent file reads as empty, so the first run creates it and its parent.
    assert.deepEqual(readJsonFile(file), {});
    assert.equal(updateJsonFile(file, config => { config.added = 1; return true; }), true);
    assert.deepEqual(read(file), { added: 1 });
    assert.equal(mode(file), 0o600);
    // Trailing newline, so the file stays diffable and editor-friendly.
    assert.match(fs.readFileSync(file, 'utf8'), /\n$/);

    // Returning anything but true is "nothing changed": no write at all, so the
    // mtime other applications watch is left alone.
    const before = fs.statSync(file).mtimeMs;
    assert.equal(updateJsonFile(file, () => false), false);
    assert.equal(fs.statSync(file).mtimeMs, before);
    // The mode is still asserted on that path, to correct a permissive file.
    fs.chmodSync(file, 0o644);
    updateJsonFile(file, () => false);
    assert.equal(mode(file), 0o600);

    // Unrelated keys survive, which is the whole point of merging.
    fs.writeFileSync(file, JSON.stringify({ added: 1, theirs: { deep: true } }));
    updateJsonFile(file, config => { config.added = 2; return true; });
    assert.deepEqual(read(file), { added: 2, theirs: { deep: true } });

    // No temporary file is left behind by a successful write.
    assert.deepEqual(fs.readdirSync(path.dirname(file)), ['config.json']);

    // An empty file is empty config; a malformed one must NOT be treated as
    // empty, or the merge would discard the settings it exists to preserve.
    const blank = path.join(dir, 'blank.json');
    fs.writeFileSync(blank, '   \n');
    assert.deepEqual(readJsonFile(blank), {});
    const broken = path.join(dir, 'broken.json');
    fs.writeFileSync(broken, '{"half":');
    assert.throws(() => readJsonFile(broken), SyntaxError);
    assert.throws(() => updateJsonFile(broken, () => true), SyntaxError);
    assert.equal(fs.readFileSync(broken, 'utf8'), '{"half":');
});
test('flat-object equality ignores key order and rejects non-objects', () => {
    assert.equal(sameFlatObject({ a: 1, b: 2 }, { b: 2, a: 1 }), true);
    assert.equal(sameFlatObject({ a: 1 }, { a: 1, b: 2 }), false);
    assert.equal(sameFlatObject({ a: 1, b: 2 }, { a: 1 }), false);
    assert.equal(sameFlatObject({ a: '1' }, { a: 1 }), false);
    for (const value of [undefined, null, 'x', 7, ['a']]) assert.equal(sameFlatObject(value, { a: 1 }), false);
});
test('the Claude statusLine hook is configured without disturbing other settings', t => {
    const dir = temporaryDir(t);
    const file = path.join(dir, 'settings.json');
    const logged = [];
    const log = line => logged.push(line);

    assert.equal(configureStatusLine({ file, log }), true);
    assert.deepEqual(read(file).statusLine, {
        type: 'command',
        command: '~/.config/tmux/claude-statusline-hook.mjs',
        refreshInterval: 60,
    });
    assert.match(logged.at(-1), /^OK .*configured/);

    // Idempotent: a second run neither rewrites nor claims it did.
    assert.equal(configureStatusLine({ file, log }), false);
    assert.match(logged.at(-1), /already configured/);

    // The user's own Claude Code settings are not this repo's to touch.
    fs.writeFileSync(file, JSON.stringify({
        statusLine: { type: 'command', command: 'something-else' },
        model: 'opus', theme: 'auto', modelSettings: { 'claude-fable-5-1': { effortLevel: 'medium' } },
    }));
    assert.equal(configureStatusLine({ file, log }), true);
    const after = read(file);
    assert.equal(after.statusLine.command, '~/.config/tmux/claude-statusline-hook.mjs');
    assert.equal(after.model, 'opus');
    assert.equal(after.theme, 'auto');
    assert.deepEqual(after.modelSettings, { 'claude-fable-5-1': { effortLevel: 'medium' } });

    // A key reshuffle by Claude Code is not a change worth a write.
    fs.writeFileSync(file, JSON.stringify({ statusLine: {
        refreshInterval: 60, command: '~/.config/tmux/claude-statusline-hook.mjs', type: 'command',
    } }));
    assert.equal(configureStatusLine({ file, log }), false);
});
test('Docker config gains the keychain helper and appends its plugin dir', t => {
    const dir = temporaryDir(t);
    const file = path.join(dir, 'config.json');
    const log = () => {};
    const brewPlugins = '/opt/homebrew/lib/docker/cli-plugins';

    assert.equal(configureDocker({ file, log }), true);
    assert.deepEqual(read(file), { credsStore: 'osxkeychain', cliPluginsExtraDirs: [brewPlugins] });
    // Can hold registry auth material even with a credential helper configured.
    assert.equal(mode(file), 0o600);
    assert.equal(configureDocker({ file, log }), false);

    // Another install's plugin directory is appended to, never replaced, and
    // currentContext and auths are left alone.
    fs.writeFileSync(file, JSON.stringify({
        currentContext: 'colima',
        auths: { 'ghcr.io': {} },
        cliPluginsExtraDirs: ['/Users/me/.docker/cli-plugins'],
    }));
    assert.equal(configureDocker({ file, log }), true);
    assert.deepEqual(read(file), {
        currentContext: 'colima',
        auths: { 'ghcr.io': {} },
        cliPluginsExtraDirs: ['/Users/me/.docker/cli-plugins', brewPlugins],
        credsStore: 'osxkeychain',
    });
    assert.equal(configureDocker({ file, log }), false);

    // A non-array value cannot be appended to, so it is normalised away rather
    // than crashing the bootstrap step.
    fs.writeFileSync(file, JSON.stringify({ credsStore: 'osxkeychain', cliPluginsExtraDirs: 'oops' }));
    assert.equal(configureDocker({ file, log }), true);
    assert.deepEqual(read(file).cliPluginsExtraDirs, [brewPlugins]);

    // A different credential helper is corrected, not preserved.
    fs.writeFileSync(file, JSON.stringify({ credsStore: 'desktop', cliPluginsExtraDirs: [brewPlugins] }));
    assert.equal(configureDocker({ file, log }), true);
    assert.equal(read(file).credsStore, 'osxkeychain');
});
test('the active Firefox profile comes from the per-install section first', () => {
    // Firefox stops updating the legacy Default=1 flag once an [Install...]
    // section exists, so that section is the one naming the profile it opens.
    assert.equal(profilePath(`
[Profile1]
Name=old
Path=abc.default
Default=1

[Install4F96D1932A9F858E]
Default=xyz.default-release
Locked=1
`), 'xyz.default-release');

    // With no [Install...] section the legacy flag is all there is.
    assert.equal(profilePath('[Profile0]\nPath=abc.default\nDefault=1\n'), 'abc.default');
    // An [Install...] section with no Default= must not shadow the legacy flag.
    assert.equal(profilePath('[InstallABC]\nLocked=1\n\n[Profile0]\nPath=abc.default\nDefault=1\n'), 'abc.default');
    // Nothing marked default at all is a normal state, not an error.
    assert.equal(profilePath('[Profile0]\nPath=abc.default\n'), null);
    assert.equal(profilePath(''), null);
    // configparser lowercased option names, so casing must not matter; comments
    // and blank lines are skipped, and an absolute path passes through as-is.
    assert.equal(profilePath('; a comment\n# another\n[InstallX]\n  default = /abs/profile  \n'), '/abs/profile');
    assert.equal(profilePath('[Profile0]\npath=abc\ndefault=1\n'), 'abc');
    // A key before any section header has no section to belong to.
    assert.equal(profilePath('Default=stray\n[InstallX]\nDefault=real\n'), 'real');
});
test('the Firefox default zoom is set globally without touching per-site levels', t => {
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

    setDefaultZoom(file, { now: 1_700_000_000_000 });
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

    // A per-site level (groupID set) belongs to the user and must survive.
    db.prepare('insert into prefs (groupID, settingID, value, timestamp) values (?, ?, ?, ?)')
        .run(7, settingId, 2.0, 1);
    // A stale duplicate global is replaced, not added to, so id order cannot
    // leave the old value winning.
    db.prepare('insert into prefs (groupID, settingID, value, timestamp) values (NULL, ?, ?, ?)')
        .run(settingId, 0.5, 2);
    db.close();

    setDefaultZoom(file, { zoom: 1.5, now: 1_700_000_001_000 });
    db = new DatabaseSync(file);
    assert.deepEqual(globals(), [{ value: 1.5, timestamp: 1_700_000_001 }]);
    assert.deepEqual(db.prepare('select groupID, value from prefs where groupID is not null').all()
        .map(row => ({ ...row })), [{ groupID: 7, value: 2.0 }]);
    // Re-running reuses the existing settings row rather than piling up more.
    assert.equal(db.prepare('select count(*) as n from settings').get().n, 2);
    db.close();
});
