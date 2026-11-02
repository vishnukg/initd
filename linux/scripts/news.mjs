#!/usr/bin/env node
// Headlines for the desktop news widget (NewsCard.qml): world, then
// Australia, then India, from Google News' RSS. Prints one JSON object on
// stdout: { updated, sections: [{ id, title, items: [{ title, source, link,
// published }], error? }] }.
//
// Google News over a per-outlet feed because it is one format with the
// outlet named in <source>, and its feed terms allow exactly this: a personal
// feed reader. The country pages use the NATION section, not the edition's
// top stories -- the Australian edition's top stories lead with US news.
//
// RSS is parsed by hand (no XML library: no package.json here, see CLAUDE.md).
// The feed is flat and machine-generated, so pulling <item> blocks and a few
// tags out of each with a regex is enough, and the tests pin the shape.
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const TOPIC = 'https://news.google.com/rss/headlines/section/topic/';

export const FEEDS = [
    { id: 'world', title: 'World', url: TOPIC + 'WORLD?hl=en-US&gl=US&ceid=US:en' },
    { id: 'australia', title: 'Australia', url: TOPIC + 'NATION?hl=en-AU&gl=AU&ceid=AU:en' },
    { id: 'india', title: 'India', url: TOPIC + 'NATION?hl=en-IN&gl=IN&ceid=IN:en' },
];

const NAMED = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

export function decodeEntities(text) {
    return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, code) => {
        if (code[0] === '#') {
            const value = code[1] === 'x' || code[1] === 'X'
                ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
            return Number.isFinite(value) ? String.fromCodePoint(value) : whole;
        }
        return NAMED[code.toLowerCase()] ?? whole;
    });
}

function tag(block, name) {
    const match = new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)</${name}>`).exec(block);
    if (!match) return '';
    const cdata = /^<!\[CDATA\[([\s\S]*)\]\]>$/.exec(match[1].trim());
    return (cdata ? cdata[1] : decodeEntities(match[1])).trim();
}

// Up to `limit` items, newest first. Google News titles end in " - <outlet>";
// that suffix is dropped when <source> names the same outlet, since the
// widget shows the outlet on its own line.
export function parseFeed(xml, limit = 8) {
    const items = [];
    for (const [, block] of String(xml).matchAll(/<item>([\s\S]*?)<\/item>/g)) {
        const source = tag(block, 'source');
        let title = tag(block, 'title');
        if (source && title.endsWith(' - ' + source))
            title = title.slice(0, -(source.length + 3));
        const link = tag(block, 'link');
        const date = new Date(tag(block, 'pubDate'));
        if (!title || !/^https?:\/\//.test(link)) continue;
        items.push({
            title,
            source,
            link,
            published: Number.isNaN(date.getTime()) ? null : date.toISOString(),
        });
    }
    items.sort((a, b) => (b.published ?? '').localeCompare(a.published ?? ''));
    return items.slice(0, limit);
}

// Every feed is fetched in parallel and fails on its own: one outage empties
// one page (with `error` set), never the whole widget.
export async function readNews({ fetchImpl = fetch, feeds = FEEDS, now = new Date(), timeoutMs = 10000 } = {}) {
    const sections = await Promise.all(feeds.map(async (feed) => {
        try {
            const response = await fetchImpl(feed.url, {
                signal: AbortSignal.timeout(timeoutMs),
                headers: { 'user-agent': 'initd-news-widget' },
            });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            return { id: feed.id, title: feed.title, items: parseFeed(await response.text()) };
        } catch (error) {
            return { id: feed.id, title: feed.title, items: [], error: error.message };
        }
    }));
    return { updated: now.toISOString(), sections };
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const news = await readNews();
    console.log(JSON.stringify(news));
    for (const section of news.sections)
        if (section.error) console.error(`news: ${section.id}: ${section.error}`);
}
