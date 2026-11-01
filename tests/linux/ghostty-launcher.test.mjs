import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { configureGhosttyLauncher, separateProcessLauncher, DESKTOP_ID } from '../../linux/scripts/ghostty-launcher.mjs';

// The shape of Fedora's packaged entry (ghostty-1.4.0-1.fc44).
const PACKAGED = [
    '[Desktop Entry]',
    'Name=Ghostty',
    'TryExec=ghostty',
    'Exec=ghostty --gtk-single-instance=true',
    'Actions=new-window;',
    'X-TerminalArgExec=-e',
    'DBusActivatable=true',
    '',
    '[Desktop Action new-window]',
    'Name=New Window',
    'Exec=ghostty --gtk-single-instance=true',
    '',
].join('\n');

function fixture(t) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'initd-ghostty-'));
    t.after(() => fs.rmSync(home, { recursive: true, force: true }));
    const desktop = path.join(home, 'system.desktop');
    fs.writeFileSync(desktop, PACKAGED);
    const dataHome = path.join(home, '.local/share');
    const target = path.join(dataHome, 'applications', DESKTOP_ID);
    return { target, dir: path.dirname(target), options: { home, dataHome, desktop, log() {} } };
}

test('Ghostty launcher drops single-instance and D-Bus activation from every action', () => {
    // Arrange / Act
    const actual = separateProcessLauncher(PACKAGED);

    // Assert
    assert.doesNotMatch(actual, /single-instance/);
    assert.doesNotMatch(actual, /DBusActivatable/);
    assert.equal(actual.match(/^Exec=ghostty$/gm).length, 2);
    assert.match(actual, /^TryExec=ghostty$/m);
    assert.match(actual, /^X-TerminalArgExec=-e$/m);
});

test('Ghostty launcher keeps other arguments and drops a bare flag too', () => {
    // Arrange
    const text = 'Exec=/usr/bin/ghostty --gtk-single-instance --title=x\n';

    // Act
    const actual = separateProcessLauncher(text);

    // Assert
    assert.equal(actual, 'Exec=/usr/bin/ghostty --title=x\n');
});

test('Ghostty launcher refuses an entry with no Ghostty Exec line', () => {
    // Arrange / Act / Assert
    assert.throws(() => separateProcessLauncher('[Desktop Entry]\nExec=kitty\n'), /No Ghostty Exec/);
});

test('Ghostty launcher shadow is written once and a re-run changes nothing', t => {
    // Arrange
    const f = fixture(t);

    // Act
    configureGhosttyLauncher(f.options);
    const first = fs.statSync(f.target).mtimeMs;
    configureGhosttyLauncher(f.options);

    // Assert
    assert.equal(fs.readFileSync(f.target, 'utf8'), separateProcessLauncher(PACKAGED));
    assert.equal(fs.statSync(f.target).mtimeMs, first);
    assert.deepEqual(fs.readdirSync(f.dir), [DESKTOP_ID]);
});

test('Ghostty launcher backs up a different existing shadow before replacing it', t => {
    // Arrange
    const f = fixture(t);
    fs.mkdirSync(f.dir, { recursive: true });
    fs.writeFileSync(f.target, 'mine\n');

    // Act
    configureGhosttyLauncher(f.options);
    const backups = fs.readdirSync(f.dir).filter(name => name.includes('.initd-backup-'));

    // Assert
    assert.equal(backups.length, 1);
    assert.equal(fs.readFileSync(path.join(f.dir, backups[0]), 'utf8'), 'mine\n');
    assert.doesNotMatch(fs.readFileSync(f.target, 'utf8'), /single-instance/);
});

test('Ghostty launcher is skipped when Ghostty is not installed', t => {
    // Arrange
    const f = fixture(t);
    const options = { ...f.options, desktop: path.join(f.options.home, 'missing.desktop') };

    // Act
    configureGhosttyLauncher(options);

    // Assert
    assert.equal(fs.existsSync(f.target), false);
});
