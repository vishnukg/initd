// linux/scripts/news.mjs: the desktop news widget's Google News fetcher.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FEEDS, decodeEntities, parseFeed, readNews } from '../../linux/scripts/news.mjs';

const item = ({ title, source = 'ABC News', link = 'https://news.google.com/rss/articles/x', date = 'Mon, 02 Nov 2026 08:00:00 GMT' }) =>
    `<item><title>${title}</title><link>${link}</link><pubDate>${date}</pubDate>`
    + `<description>&lt;a href="x"&gt;ignored&lt;/a&gt;</description>`
    + `<source url="https://example.com">${source}</source></item>`;
const feed = (...items) => `<?xml version="1.0"?><rss><channel><title>Top stories</title>${items.join('')}</channel></rss>`;

test('the pages run world, then Australia, then India', () => {
    assert.deepEqual(FEEDS.map((f) => f.id), ['world', 'australia', 'india']);
    // Country pages are the NATION section, not the edition's top stories.
    assert.match(FEEDS[1].url, /NATION\?.*gl=AU/);
    assert.match(FEEDS[2].url, /NATION\?.*gl=IN/);
});

test('decodeEntities handles named, decimal and hex references', () => {
    assert.equal(decodeEntities('Q&amp;A &lt;b&gt; &quot;x&quot; &#39;y&#39; &#x2019; &bogus;'),
        'Q&A <b> "x" \'y\' ’ &bogus;');
});

test('parseFeed drops the outlet suffix and keeps the outlet separately', () => {
    // Arrange
    const xml = feed(item({ title: 'Rates on hold &amp; markets rally - ABC News' }));
    // Act
    const [first] = parseFeed(xml);
    // Assert
    assert.deepEqual(first, {
        title: 'Rates on hold & markets rally',
        source: 'ABC News',
        link: 'https://news.google.com/rss/articles/x',
        published: '2026-11-02T08:00:00.000Z',
    });
});

test('parseFeed keeps a title whose suffix names a different outlet', () => {
    const [first] = parseFeed(feed(item({ title: 'Story - Reuters', source: 'AP' })));
    assert.equal(first.title, 'Story - Reuters');
});

test('parseFeed sorts newest first, caps the count, and skips unusable items', () => {
    // Arrange
    const xml = feed(
        item({ title: 'old', date: 'Mon, 02 Nov 2026 01:00:00 GMT' }),
        item({ title: 'new', date: 'Mon, 02 Nov 2026 09:00:00 GMT' }),
        item({ title: 'no date', date: 'not a date' }),
        item({ title: '', date: 'Mon, 02 Nov 2026 10:00:00 GMT' }),
        item({ title: 'script link', link: 'javascript:alert(1)' }),
        item({ title: 'mid', date: 'Mon, 02 Nov 2026 05:00:00 GMT' }),
    );
    // Act
    const items = parseFeed(xml, 3);
    // Assert
    assert.deepEqual(items.map((i) => i.title), ['new', 'mid', 'old']);
    assert.equal(parseFeed(xml).at(-1).published, null);
});

test('parseFeed reads CDATA titles verbatim', () => {
    const [first] = parseFeed(feed(item({ title: '<![CDATA[Tom & Jerry <live>]]>', source: '' })));
    assert.equal(first.title, 'Tom & Jerry <live>');
});

test('parseFeed returns nothing for junk', () => {
    assert.deepEqual(parseFeed(''), []);
    assert.deepEqual(parseFeed('<html>captcha</html>'), []);
    assert.deepEqual(parseFeed(undefined), []);
});

test('readNews fails one page at a time', async () => {
    // Arrange
    const fetchImpl = async (url) => {
        if (url.includes('gl=AU')) return { ok: false, status: 503, text: async () => '' };
        if (url.includes('gl=IN')) throw new Error('timed out');
        return { ok: true, status: 200, text: async () => feed(item({ title: 'World story - ABC News' })) };
    };
    // Act
    const news = await readNews({ fetchImpl, now: new Date('2026-11-02T09:00:00Z') });
    // Assert
    assert.equal(news.updated, '2026-11-02T09:00:00.000Z');
    assert.deepEqual(news.sections.map((s) => [s.id, s.items.length, s.error]), [
        ['world', 1, undefined],
        ['australia', 0, 'HTTP 503'],
        ['india', 0, 'timed out'],
    ]);
});
