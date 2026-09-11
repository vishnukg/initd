// Merging a key or two into a JSON config file this repo does not own.
//
// Both callers edit a file that also holds the user's own settings -
// ~/.claude/settings.json carries modelSettings and theme, ~/.docker/config.json
// carries currentContext and any registry auths - so neither can be a
// MANAGED_LINKS symlink and neither may be rewritten wholesale. This is the one
// place that invariant is implemented.
import fs from 'node:fs';
import path from 'node:path';

// An absent file is an empty object. A malformed one is NOT: silently replacing
// a file we failed to parse would discard exactly the settings this exists to
// preserve, so the caller fails loudly and the user keeps their file.
export function readJsonFile(file) {
    let text;
    try { text = fs.readFileSync(file, 'utf8'); }
    catch (error) {
        if (error.code === 'ENOENT') return {};
        throw error;
    }
    return text.trim() ? JSON.parse(text) : {};
}

// `mutate` edits the parsed object in place and returns true when it changed
// something. Writing only then keeps every caller idempotent and leaves the
// file's mtime alone on a re-run, which matters because these are live config
// files their owning applications watch.
//
// 0600 because both files are personal and one can hold registry credentials.
// It is asserted even when the JSON did not change, so a file left more
// permissive by an earlier run or by the tool that created it gets corrected.
export function updateJsonFile(file, mutate, { mode = 0o600 } = {}) {
    const config = readJsonFile(file);
    if (mutate(config) !== true) {
        if (fs.existsSync(file)) fs.chmodSync(file, mode);
        return false;
    }
    fs.mkdirSync(path.dirname(file), { recursive: true });
    // Through a temporary file so a crash cannot truncate a config holding the
    // user's own settings, and created at its final mode so the content is never
    // briefly world-readable.
    const temporary = `${file}.initd-${process.pid}.tmp`;
    try {
        fs.writeFileSync(temporary, `${JSON.stringify(config, null, 2)}\n`, { mode });
        fs.renameSync(temporary, file);
    } finally {
        try { fs.unlinkSync(temporary); } catch { /* renamed into place already */ }
    }
    return true;
}

// Order-insensitive equality for the flat objects these callers compare, so a
// key reshuffle by the owning application does not count as a change.
export function sameFlatObject(value, wanted) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
    const keys = Object.keys(wanted);
    return keys.length === Object.keys(value).length && keys.every(key => value[key] === wanted[key]);
}
