import { readAdmin, updateAdmin } from './adminDb.js';
import { fetchWatch } from './crawlLayn.js';
import { detectGenre } from '../routes/catalog.js';

const SEEDS = [
  'avaz-oxun-kulib-yashaylik-nomli-konsert-dasturi-2026_yHBruKaAkmnYPOj',
  'farz-uzbek-kino-2026-premera-1080',
  'ip-man-adolat-uchun-kurash-2026-tarjima-kino-boevik-o-039-zbek-tilida_yrlpaZgDpqwkYW3',
  'maskarad-shou-yangi-yil-soni-2026_8ap3DwJG27q5AAC',
];
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function decode(s) {
  return String(s || '')
    .replace(/&#0?39;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

export async function crawlNew(maxPages = 60) {
  const data = await readAdmin();
  const known = new Set((data.catalog || []).map((c) => c.key));
  const existing = (data.catalog || []).length;
  const seen = new Set();
  const found = [];
  const queue = [...SEEDS];
  while (queue.length && seen.size < maxPages) {
    const slug = queue.shift();
    if (!slug || seen.has(slug)) continue;
    seen.add(slug);
    try {
      const page = await fetchWatch(slug);
      if (page.title && page.oid && page.vid) {
        const key = `${page.oid}_${page.vid}`;
        if (!known.has(key)) {
          known.add(key);
          const title = decode(page.title) || 'Без названия';
          found.push({
            key,
            title,
            thumb: page.thumb || '',
            durationSec: 0,
            genre: detectGenre(title),
            views: 0,
            addedAt: Date.now(),
          });
        }
      }
      for (const r of (page.related || []).slice(0, 10)) {
        if (!seen.has(r)) queue.push(r);
      }
    } catch {}
    await sleep(400);
  }
  if (!found.length) {
    console.log(
      `[autocrawl] existing=${existing} fetched=0 — catalog untouched`
    );
    return { added: 0, seen: seen.size };
  }
  const res = await updateAdmin((fresh) => {
    const list = Array.isArray(fresh.catalog) ? fresh.catalog : [];
    const freshKnown = new Set(list.map((c) => c.key));
    let n = 0;
    for (const c of found) {
      if (freshKnown.has(c.key)) continue;
      freshKnown.add(c.key);
      list.unshift(c);
      n++;
    }
    fresh.catalog = list.slice(0, 2000);
    return { final: fresh.catalog.length, added: n };
  });
  console.log(
    `[autocrawl] existing=${existing} fetched=${found.length} added=${res.added} final=${res.final}`
  );
  return { added: res.added, seen: seen.size };
}

export function startAutoCrawl() {
  const run = async () => {
    try {
      const r = await crawlNew(60);
      console.log(`[autocrawl] added=${r.added} seen=${r.seen}`);
    } catch (error) {
      console.error('[autocrawl] failed:', error.message);
    }
  };
  setTimeout(run, 10 * 60 * 1000);
  setInterval(run, WEEK_MS);
}
