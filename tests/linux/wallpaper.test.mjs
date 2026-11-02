// linux/scripts/wallpaper.mjs: collections, ordering, sizing and cache keys.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { cachePath, isWallpaper, listCollections, listImages, neighbour, targetSize } from '../../linux/scripts/wallpaper.mjs';

test('isWallpaper takes images and skips collection previews and dotfiles', () => {
    for (const name of ['a.jpg', 'B.JPEG', 'c.png', 'd.webp']) assert.ok(isWallpaper(name), name);
    for (const name of ['preview.jpg', 'README.md', 'sources.json', 'index.html', '.hidden.jpg', 'x.prompt.txt'])
        assert.ok(!isWallpaper(name), name);
});

test('listImages sorts numbered files in their intended order', () => {
    // Arrange
    const readdir = () => ['10-ten.jpg', '2-two.jpg', 'preview.jpg', '1-one.png', 'notes.txt'];
    // Act
    const images = listImages('/w/cosmos', readdir);
    // Assert
    assert.deepEqual(images.map((p) => path.basename(p)), ['1-one.png', '2-two.jpg', '10-ten.jpg']);
    assert.deepEqual(listImages('/missing', () => { throw new Error('ENOENT'); }), []);
});

test('listCollections lists subdirectories that hold wallpapers', () => {
    const dir = (name) => ({ name, isDirectory: () => true });
    const file = (name) => ({ name, isDirectory: () => false });
    const readdir = (p, options) => {
        if (options) return [dir('cosmos'), dir('empty'), dir('.git'), file('wallpaper.jpg')];
        return p.endsWith('cosmos') ? ['a.jpg'] : ['README.md'];
    };
    assert.deepEqual(listCollections('/w', readdir), ['/w/cosmos']);
});

test('neighbour steps through a collection, wrapping at both ends', () => {
    const list = ['/a.jpg', '/b.jpg', '/c.jpg'];
    assert.equal(neighbour(list, '/b.jpg', 1), '/c.jpg');
    assert.equal(neighbour(list, '/c.jpg', 1), '/a.jpg');
    assert.equal(neighbour(list, '/a.jpg', -1), '/c.jpg');
    assert.equal(neighbour(list, '/elsewhere.jpg', 1), '/a.jpg');
    assert.equal(neighbour([], '/a.jpg', 1), null);
});

test('targetSize covers the largest monitor, accounting for rotation', () => {
    // Arrange: the laptop panel plus a 4K monitor rotated to portrait.
    const json = JSON.stringify([
        { width: 2560, height: 1600, transform: 0 },
        { width: 3840, height: 2160, transform: 1 },
    ]);
    // Act / Assert
    assert.deepEqual(targetSize(json), { width: 2560, height: 3840 });
    assert.deepEqual(targetSize('[{"width":3840,"height":2160,"transform":0}]'), { width: 3840, height: 2160 });
    assert.deepEqual(targetSize('not json'), { width: 2560, height: 1600 });
    assert.deepEqual(targetSize('[]'), { width: 2560, height: 1600 });
});

test('cachePath changes with the size and with the original\'s mtime', () => {
    const size = { width: 2560, height: 1600 };
    const a = cachePath('/w/cosmos/08-orion.jpg', size, 1000, '/cache');
    assert.match(a, /^\/cache\/08-orion-2560x1600-[0-9a-f]{16}\.jpg$/);
    assert.equal(cachePath('/w/cosmos/08-orion.jpg', size, 1000, '/cache'), a);
    assert.notEqual(cachePath('/w/cosmos/08-orion.jpg', size, 2000, '/cache'), a);
    assert.notEqual(cachePath('/w/cosmos/08-orion.jpg', { width: 3840, height: 2160 }, 1000, '/cache'), a);
});
