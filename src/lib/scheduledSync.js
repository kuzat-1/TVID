import { readAdmin, writeAdmin } from './adminDb.js';

const EIGHT_HOURS_MS = 8 * 60 * 60 * 1000;
const FOURTEEN_DAYS_MS = 14 * 24 * 60 * 60 * 1000;
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || '123456tanho';
const VK_SVC = process.env.VK_SERVICE_TOKEN || '';
const SELF_BASE =
  `http://127.0.0.1:${process.env.BACKEND_PORT || 3000}`;
let running = false;

async function refreshStaleThumbs() {
  try {
    const data = await readAdmin();
    const now = Date.now();
    const stale = (data.catalog || []).filter(
      (c) => !c.thumbTs || now - c.thumbTs > FOURTEEN_DAYS_MS
    ).slice(0, 200);
    if (!stale.length) return;
    let upd = 0;
    for (const c of stale) {
      try {
        const url =
          `https://api.vk.com/method/video.get?videos=${c.key}` +
          `&access_token=${VK_SVC}&v=5.131`;
        const r = await fetch(url, {
          signal: AbortSignal.timeout(12000),
        }).then((r) => r.json());
        const it = (r?.response?.items || [])[0];
        const frames = Array.isArray(it?.first_frame)
          ? it.first_frame
          : [];
        if (frames.length && frames[frames.length - 1].url) {
          c.thumb = String(frames[frames.length - 1].url);
          c.thumbTs = Date.now();
          upd++;
        }
      } catch {}
      await new Promise((r) => setTimeout(r, 300));
    }
    await writeAdmin(data);
    console.log(`[thumb-refresh] updated=${upd} checked=${stale.length}`);
  } catch (error) {
    console.error('[thumb-refresh] failed:', error.message || error);
  }
}

async function syncOnce() {
  if (running) return;
  running = true;
  try {
    const data = await readAdmin();
    const bySource = new Map();
    for (const c of data.catalog || []) {
      const url = String(c.sourceUrl || '').trim();
      if (!url) continue;
      if (!bySource.has(url)) {
        bySource.set(url, String(c.source || url).slice(0, 80));
      }
    }
    for (const [url, name] of bySource) {
      try {
        const res = await fetch(`${SELF_BASE}/api/sync`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${ADMIN_TOKEN}`,
          },
          body: JSON.stringify({ url }),
          signal: AbortSignal.timeout(10 * 60 * 1000),
        });
        const result = await res.json().catch(() => ({}));
        console.log(
          `[scheduled-sync] ${name}: found=${result.found ?? '?'} added=${result.added ?? '?'}`
        );
      } catch (error) {
        console.error(
          `[scheduled-sync] failed ${name}:`,
          error.message || error
        );
      }
    }
  } catch (error) {
    console.error('[scheduled-sync] failed:', error.message || error);
  }
  running = false;
}

export function startScheduledSync() {
  setTimeout(async () => {
    await syncOnce();
    await refreshStaleThumbs();
  }, 5 * 60 * 1000);
  setInterval(async () => {
    await syncOnce();
    await refreshStaleThumbs();
  }, EIGHT_HOURS_MS);
}
