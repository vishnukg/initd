#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const filename = fileURLToPath(import.meta.url);

export const DESKTOP_ID = 'com.mitchellh.ghostty.desktop';

// Fedora's entry launches Ghostty single-instance two ways: the Exec lines pass
// --gtk-single-instance=true (a CLI flag, which beats the config's
// `gtk-single-instance = false`), and DBusActivatable=true makes launchers that
// honour it start app-com.mitchellh.ghostty.service instead of Exec at all.
// Either way every rofi/.desktop window joins one long-lived process, which is
// where Ghostty's window-lifecycle leak accumulates and is never handed back.
// Dropping both gives each launch its own process, like the keybind already
// does. Cost: ~680 ms per launch instead of ~270 ms for a single-instance client.
export function separateProcessLauncher(text) {
    let count = 0;
    const result = text
        .replace(/^Exec=(\S*ghostty)(.*)$/gm, (_, binary, args) => {
            count++;
            return `Exec=${binary}${args.replace(/\s+--gtk-single-instance(?:=\S+)?/g, '')}`;
        })
        .replace(/^DBusActivatable=.*\n?/gm, '');
    if (!count) throw new Error('No Ghostty Exec entries found.');
    return result;
}

// Regenerated from the packaged entry on every run, so a package update that
// changes the entry lands on the next setup.sh. The shadow in
// ~/.local/share/applications wins over /usr/share/applications by desktop ID.
export function configureGhosttyLauncher({
    home = process.env.HOME,
    dataHome = process.env.XDG_DATA_HOME || path.join(home, '.local/share'),
    desktop = path.join('/usr/share/applications', DESKTOP_ID),
    log = console.log,
} = {}) {
    if (!fs.existsSync(desktop)) {
        log('Ghostty is not installed — skipping its launcher.');
        return;
    }
    const target = path.join(dataHome, 'applications', DESKTOP_ID);
    const contents = separateProcessLauncher(fs.readFileSync(desktop, 'utf8'));
    if (fs.existsSync(target) && fs.readFileSync(target, 'utf8') === contents) {
        log('Ghostty launcher already opens one process per window.');
        return;
    }
    fs.mkdirSync(path.dirname(target), { recursive: true });
    if (fs.existsSync(target)) fs.copyFileSync(target, `${target}.initd-backup-${Date.now()}`, fs.constants.COPYFILE_EXCL);
    const temporary = `${target}.initd-${process.pid}.tmp`;
    try {
        fs.writeFileSync(temporary, contents, { flag: 'wx', mode: 0o644 });
        fs.renameSync(temporary, target);
    } finally {
        if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
    }
    log('Ghostty launcher: one process per window (no single-instance server).');
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === filename) {
    try {
        if (process.argv.length !== 2) throw new Error('Usage: ghostty-launcher.mjs');
        configureGhosttyLauncher();
    } catch (error) {
        console.error(`ghostty-launcher: ${error.message}`);
        process.exitCode = 1;
    }
}
