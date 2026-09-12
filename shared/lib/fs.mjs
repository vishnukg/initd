import fs from 'node:fs';
import path from 'node:path';

// Unlike existsSync, this sees broken symlinks and reports permission errors.
export function pathStat(file) {
    try { return fs.lstatSync(file); }
    catch (error) {
        if (error.code === 'ENOENT') return null;
        throw error;
    }
}

export function pointsTo(file, source) {
    return pathStat(file)?.isSymbolicLink() === true && fs.readlinkSync(file) === source;
}

export function defaultBackupRoot(home = process.env.HOME) {
    const stamp = new Date().toISOString().replace(/[-:.TZ]/g, '');
    return process.env.BACKUP_ROOT || path.join(home, '.config/initd-backups', `${stamp}.${process.pid}`);
}

export function backupPath(file, { home = process.env.HOME, backupRoot, log = console.log } = {}) {
    if (!pathStat(file)) return null;
    if (!backupRoot) throw new Error('backupRoot is required before backing up a path');
    const relative = path.relative(home, file);
    // Some Linux links live inside a checkout outside HOME. Never let '..'
    // escape the backup directory; retain their absolute path under external/.
    const insideHome = relative && relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
    const base = path.join(backupRoot, insideHome ? relative : path.join('external', path.resolve(file).slice(1)));
    let backup = base;
    let suffix = 0;
    while (pathStat(backup)) backup = `${base}.${++suffix}`;
    fs.mkdirSync(path.dirname(backup), { recursive: true });
    log(`!! Backing up unmanaged ${file} -> ${backup}`);
    try {
        fs.renameSync(file, backup);
    } catch (error) {
        if (error.code !== 'EXDEV') throw error;
        // Match mv across filesystems. Remove the original only after copying.
        fs.cpSync(file, backup, { recursive: true, dereference: false, verbatimSymlinks: true, force: false, errorOnExist: true });
        fs.rmSync(file, { recursive: true });
    }
    return backup;
}

export function installLink(file, source, options = {}) {
    const log = options.log || console.log;
    if (!pathStat(source)) throw new Error(`Managed source path does not exist: ${source}`);
    if (pointsTo(file, source)) {
        log(`==> Already linked: ${file}`);
        return false;
    }
    backupPath(file, options);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.symlinkSync(source, file);
    log(`==> Linked ${file} -> ${source}`);
    return true;
}

export function removeLink(file, source, { dryRun = false, log = console.log } = {}) {
    const stat = pathStat(file);
    if (!stat) {
        log(`==> Already absent: ${file}`);
        return false;
    }
    if (!stat.isSymbolicLink() || !pointsTo(file, source)) {
        log(`!! Leaving path outside initd ownership: ${file}`);
        return false;
    }
    if (dryRun) log(`==> Would remove: ${file} -> ${source}`);
    else {
        fs.unlinkSync(file);
        log(`==> Removed: ${file}`);
    }
    return true;
}
