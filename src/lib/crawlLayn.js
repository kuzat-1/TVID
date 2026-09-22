import axios from 'axios';

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
const BASE = 'https://layn.su';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function fetchWatch(slug) {
  const url = `${BASE}/watch/${slug}`;
  const resp = await axios.get(url, {
    headers: { 'User-Agent': UA },
    timeout: 20000,
    maxRedirects: 3,
    validateStatus: (s) => s === 200,
  });
  const html = String(resp.data || '');
  const title =
    (html.match(/<meta property="og:title" content="([^"]{1,150})/) || [])[1] ||
    '';
  const thumb =
    (html.match(/<meta property="og:image" content="([^"]{1,300})/) || [])[1] ||
    '';
  const oid = (html.match(/var oid = "(-?\d+)"/) || [])[1] || '';
  const vid = (html.match(/var vid = "(\d+)"/) || [])[1] || '';
  const slugSet = new Set();
  const re = /\/watch\/([a-zA-Z0-9_-]+)/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    if (m[1] && m[1] !== slug) slugSet.add(m[1]);
  }
  return { slug, title, thumb, oid, vid, related: [...slugSet] };
}

export async function crawlCatalog(seeds, maxPages = 40) {
  const seen = new Set();
  const queue = [...seeds];
  const items = [];
  while (queue.length && seen.size < maxPages) {
    const slug = queue.shift();
    if (!slug || seen.has(slug)) continue;
    seen.add(slug);
    try {
      const page = await fetchWatch(slug);
      if (page.title) {
        items.push({
          slug: page.slug,
          title: page.title,
          thumb: page.thumb,
          oid: page.oid,
          vid: page.vid,
          vkKey: page.oid && page.vid ? `${page.oid}_${page.vid}` : '',
        });
      }
      for (const r of page.related.slice(0, 12)) {
        if (!seen.has(r)) queue.push(r);
      }
    } catch {
      // skip dead pages
    }
    await sleep(400);
  }
  return items;
}
