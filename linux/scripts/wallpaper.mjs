#!/usr/bin/env node
// Wallpapers: switching, a picker, hourly rotation, and the colour theme that
// follows (theme.mjs). The image collections are the vishnukg/wallpapers
// clone in ~/.local/share/wallpapers (linux/scripts/wallpapers.sh).
//
//   set <image>        show <image> and re-theme the desktop from it
//   next | prev        the next/previous image in the current one's collection
//   random             a random image from the current collection
//   pick               rofi picker: a collection, then an image, with thumbnails
//   rotate             `next`, if rotation is on (the hourly timer runs this)
//   rotation on|off|toggle|status
//   ensure             make sure the wallpaper link exists (every login)
//
// hyprpaper.conf points at ~/.local/state/initd/wallpaper, a link to the
// current image *pre-scaled to the largest monitor* in ~/.cache/initd. So
// login shows the right wallpaper with no restore step racing hyprpaper's
// start, and hyprpaper decodes a ~4 MP file instead of a 77 MP original (the
// cosmos set is up to 8948x8597). The original's path is kept beside the
// link, so `next` knows the collection.
import { execFile, execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { applyTheme, ensureTheme } from './theme.mjs';

const HOME = os.homedir();
export const LIBRARY = path.join(HOME, '.local/share/wallpapers');
export const DEFAULT_IMAGE = path.join(LIBRARY, 'minimal/pastel-blue-glow.jpg');
const STATE = path.join(HOME, '.local/state/initd');
const LINK = path.join(STATE, 'wallpaper');
const SOURCE_FILE = path.join(STATE, 'wallpaper-source');
const ROTATE_FILE = path.join(STATE, 'wallpaper-rotate');
const CACHE = path.join(HOME, '.cache/initd/wallpapers');
const THUMBS = path.join(HOME, '.cache/initd/thumbnails');

const IMAGE = /\.(jpe?g|png|webp)$/i;
// Collection previews and the like are not wallpapers.
const NOT_WALLPAPERS = new Set(['preview.jpg', 'preview.png']);

export function isWallpaper(name) {
    return IMAGE.test(name) && !NOT_WALLPAPERS.has(name.toLowerCase()) && !name.startsWith('.');
}

// The images directly in `dir`, sorted by name (the collections number their
// files, so this is their intended order).
export function listImages(dir, readdir = fs.readdirSync) {
    let names;
    try {
        names = readdir(dir);
    } catch {
        return [];
    }
    return names.filter(isWallpaper).sort((a, b) => a.localeCompare(b, 'en', { numeric: true }))
        .map((name) => path.join(dir, name));
}

// Collections: subdirectories of the library with at least one wallpaper.
export function listCollections(library = LIBRARY, readdir = fs.readdirSync) {
    let entries;
    try {
        entries = readdir(library, { withFileTypes: true });
    } catch {
        return [];
    }
    return entries.filter((entry) => entry.isDirectory() && !entry.name.startsWith('.'))
        .map((entry) => path.join(library, entry.name))
        .filter((dir) => listImages(dir, readdir).length > 0)
        .sort();
}

// The image `step` places from `current` in `list`, wrapping; the first image
// if `current` is not in it.
export function neighbour(list, current, step) {
    if (list.length === 0) return null;
    const index = list.indexOf(current);
    if (index < 0) return list[0];
    return list[(((index + step) % list.length) + list.length) % list.length];
}

// The largest physical size across `hyprctl monitors -j`, so one scaled copy
// covers every monitor (hyprpaper's cover fit handles the aspect).
export function targetSize(monitorsJson) {
    let width = 0, height = 0;
    try {
        for (const m of JSON.parse(monitorsJson)) {
            const transposed = m.transform % 2 === 1;
            width = Math.max(width, transposed ? m.height : m.width);
            height = Math.max(height, transposed ? m.width : m.height);
        }
    } catch {
        // Fall through to the default.
    }
    return width > 0 && height > 0 ? { width, height } : { width: 2560, height: 1600 };
}

// Cache file for `source` scaled to `size`: keyed by path, size and mtime, so
// an edited original gets a fresh copy.
export function cachePath(source, size, mtimeMs, cache = CACHE) {
    const key = crypto.createHash('sha1').update(`${source}\0${size.width}x${size.height}\0${mtimeMs}`).digest('hex').slice(0, 16);
    return path.join(cache, `${path.parse(source).name}-${size.width}x${size.height}-${key}.jpg`);
}

function run(command, args, options = {}) {
    // stdin stays open only when there is input to give (the rofi picker's
    // list); with 'ignore' execFileSync silently drops `input`.
    const stdin = options.input === undefined ? 'ignore' : 'pipe';
    return execFileSync(command, args, { encoding: 'utf8', timeout: 60000, stdio: [stdin, 'pipe', 'pipe'], ...options });
}

function scaled(source) {
    let monitors = '[]';
    try {
        monitors = run('hyprctl', ['monitors', '-j']);
    } catch {
        // Not in Hyprland (setup from a TTY): use the default size.
    }
    const size = targetSize(monitors);
    const target = cachePath(source, size, fs.statSync(source).mtimeMs);
    if (!fs.existsSync(target)) {
        fs.mkdirSync(path.dirname(target), { recursive: true });
        const temp = `${target}.${process.pid}.tmp.jpg`;
        run('magick', [source, '-auto-orient', '-resize', `${size.width}x${size.height}^`, '-gravity', 'center',
            '-extent', `${size.width}x${size.height}`, '-strip', '-quality', '90', temp]);
        fs.renameSync(temp, target);
    }
    return target;
}

function relink(target) {
    fs.mkdirSync(STATE, { recursive: true });
    const temp = `${LINK}.${process.pid}.tmp`;
    fs.symlinkSync(target, temp);
    fs.renameSync(temp, LINK);
}

export function currentSource() {
    try {
        const source = fs.readFileSync(SOURCE_FILE, 'utf8').trim();
        if (source && fs.existsSync(source)) return source;
    } catch {
        // No wallpaper chosen yet.
    }
    return DEFAULT_IMAGE;
}

export function setWallpaper(source) {
    source = path.resolve(source);
    if (!fs.existsSync(source) || !IMAGE.test(source)) throw new Error(`not an image: ${source}`);
    const image = scaled(source);
    relink(image);
    fs.writeFileSync(SOURCE_FILE, source + '\n');
    try {
        run('hyprctl', ['hyprpaper', 'wallpaper', `,${image}`]);
    } catch (error) {
        // hyprpaper not running: the link is right for its next start.
        console.error(`wallpaper: hyprpaper did not take it (${error.message.split('\n')[0]})`);
    }
    try {
        applyTheme(image);
    } catch (error) {
        // matugen missing or failed: the wallpaper changed, the theme did not.
        console.error(`wallpaper: theme not updated (${error.message})`);
    }
    return image;
}

export function ensureWallpaper() {
    ensureTheme();
    let target = null;
    try {
        target = fs.readlinkSync(LINK);
    } catch {
        // No link yet.
    }
    if (target && fs.existsSync(target)) return target;
    // Missing, or its cached copy was cleaned: rebuild from the source.
    const source = currentSource();
    if (!fs.existsSync(source)) return null;
    try {
        const image = scaled(source);
        relink(image);
        return image;
    } catch {
        // No ImageMagick yet: point at the original.
        relink(source);
        return source;
    }
}

function step(n) {
    const current = currentSource();
    const next = neighbour(listImages(path.dirname(current)), current, n);
    if (!next) throw new Error('no wallpapers in the current collection');
    return setWallpaper(next);
}

function thumbnailPath(source) {
    return cachePath(source, { width: 320, height: 200 }, fs.statSync(source).mtimeMs, THUMBS);
}

// Missing thumbnails for `sources`, four magick processes at a time (~0.3 s
// each on an 8K original; a 45-image collection is ~4 s on first open, then
// cached). Returns each source's thumbnail path, in order.
async function thumbnails(sources, workers = 4) {
    fs.mkdirSync(THUMBS, { recursive: true });
    const targets = sources.map(thumbnailPath);
    const todo = sources.map((source, i) => [source, targets[i]]).filter(([, target]) => !fs.existsSync(target));
    const make = ([source, target]) => new Promise((resolve) => {
        const temp = `${target}.${process.pid}.tmp.jpg`;
        // The [640x400] hint makes libjpeg decode at reduced size: fast even on 8K originals.
        execFile('magick', [source + (/\.jpe?g$/i.test(source) ? '[640x400]' : ''), '-auto-orient', '-thumbnail',
            '320x200^', '-gravity', 'center', '-extent', '320x200', '-quality', '82', temp], { timeout: 60000 }, (error) => {
            if (!error) fs.renameSync(temp, target);
            resolve();
        });
    });
    const queue = todo.slice();
    await Promise.all(Array.from({ length: Math.min(workers, queue.length) }, async () => {
        while (queue.length) await make(queue.shift());
    }));
    return targets;
}

function rofiGrid(prompt, entries) {
    // label \0icon\x1f<path>, one per line; -format i returns the index.
    const input = entries.map(([label, icon]) => `${label}\0icon\x1f${icon}`).join('\n');
    try {
        const out = run('rofi', ['-dmenu', '-i', '-show-icons', '-format', 'i', '-p', prompt,
            '-theme-str', 'window { width: 860px; } listview { columns: 3; lines: 3; } '
                + 'element { orientation: vertical; padding: 10px; } '
                + 'element-icon { size: 150px; } element-text { horizontal-align: 0.5; }'],
        { input, timeout: 0 });
        const index = parseInt(out.trim(), 10);
        return Number.isInteger(index) ? index : -1;
    } catch {
        return -1; // Escape.
    }
}

async function pick() {
    const collections = listCollections();
    if (collections.length === 0) throw new Error(`no collections in ${LIBRARY}`);
    const coverSources = collections.map((dir) =>
        ['preview.jpg', 'preview.png'].map((n) => path.join(dir, n)).find((p) => fs.existsSync(p)) || listImages(dir)[0]);
    const covers = await thumbnails(coverSources);
    const c = rofiGrid('Collection', collections.map((dir, i) => [path.basename(dir), covers[i]]));
    if (c < 0) return null;
    const images = listImages(collections[c]);
    const thumbs = await thumbnails(images);
    const i = rofiGrid(path.basename(collections[c]), images.map((img, n) => [path.parse(img).name, thumbs[n]]));
    if (i < 0) return null;
    return setWallpaper(images[i]);
}

export function rotationOn() {
    return fs.existsSync(ROTATE_FILE);
}

function setRotation(on) {
    fs.mkdirSync(STATE, { recursive: true });
    if (on) fs.writeFileSync(ROTATE_FILE, '');
    else fs.rmSync(ROTATE_FILE, { force: true });
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const [command, arg] = process.argv.slice(2);
    try {
        switch (command) {
        case 'set':
            if (!arg) throw new Error('usage: wallpaper.mjs set <image>');
            setWallpaper(arg);
            break;
        case 'next': step(1); break;
        case 'prev': step(-1); break;
        case 'random': {
            const list = listImages(path.dirname(currentSource()));
            if (list.length) setWallpaper(list[Math.floor(Math.random() * list.length)]);
            break;
        }
        case 'pick': await pick(); break;
        case 'rotate': if (rotationOn()) step(1); break;
        case 'rotation':
            if (arg === 'on' || arg === 'off') setRotation(arg === 'on');
            else if (arg === 'toggle') setRotation(!rotationOn());
            console.log(rotationOn() ? 'on' : 'off');
            break;
        case 'ensure': ensureWallpaper(); break;
        case 'current': console.log(currentSource()); break;
        default:
            throw new Error('usage: wallpaper.mjs set <image> | next | prev | random | pick | rotate | rotation on|off|toggle|status | ensure | current');
        }
    } catch (error) {
        console.error(`wallpaper: ${error.message}`);
        process.exitCode = 1;
    }
}
