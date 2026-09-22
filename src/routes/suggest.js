import { Router } from 'express';
import { readAdmin, updateAdmin } from '../lib/adminDb.js';
import { resolveVkMeta } from '../services/vkParseService.js';
import { detectGenre } from './catalog.js';

const router = Router();
const ADMIN_TOKEN =
  process.env.ADMIN_TOKEN || '123456tanho';
const suggestHits = new Map();

function requireAdmin(req, res, next) {
  const header = req.headers.authorization || '';
  if (header === `Bearer ${ADMIN_TOKEN}`) return next();
  return res
    .status(401)
    .json({ success: false, error: 'Unauthorized' });
}

function clientIp(req) {
  return (
    req.headers['cf-connecting-ip'] ||
    req.headers['x-forwarded-for']?.toString().split(',')[0].trim() ||
    req.ip ||
    'unknown'
  );
}

router.post('/', async (req, res) => {
  try {
    const url = String(req.body?.url || '').trim().slice(0, 300);
    if (!/(-?\d+)_(\d+)/.test(url) && !/^https?:\/\//.test(url)) {
      return res
        .status(400)
        .json({ success: false, error: 'bad link' });
    }
    const ip = clientIp(req);
    const day = new Date().toISOString().slice(0, 10);
    const k = `${ip}:${day}`;
    const n = (suggestHits.get(k) || 0) + 1;
    if (n > 5) {
      return res
        .status(429)
        .json({ success: false, error: 'limit: 5 per day' });
    }
    suggestHits.set(k, n);
    const res2 = await updateAdmin((data) => {
      const list = Array.isArray(data.suggestions)
        ? data.suggestions
        : [];
      if (list.some((s) => s.url === url)) return { duplicate: true };
      list.unshift({
        url,
        ip,
        ts: new Date().toISOString(),
      });
      data.suggestions = list.slice(0, 200);
      return { duplicate: false };
    });
    res.json({ success: true, duplicate: res2.duplicate });
  } catch (error) {
    res.status(500).json({ success: false, error: 'failed' });
  }
});

router.get('/', requireAdmin, async (req, res) => {
  try {
    const data = await readAdmin();
    res.json({ success: true, items: data.suggestions || [] });
  } catch (error) {
    res.status(500).json({ success: false, error: 'failed' });
  }
});

router.post('/:idx/approve', requireAdmin, async (req, res) => {
  try {
    const data = await readAdmin();
    const list = Array.isArray(data.suggestions)
      ? data.suggestions
      : [];
    const idx = Number(req.params.idx);
    const item = list[idx];
    if (!item) {
      return res
        .status(404)
        .json({ success: false, error: 'not found' });
    }
    let meta = null;
    let reason = 'unresolvable';
    try {
      meta = await resolveVkMeta(item.url);
    } catch (e) {
      if (String(e.message || '').includes('no_player')) {
        reason = 'no embed — приватное, удалённое или 18+';
      }
    }
    if (!meta) {
      return res.status(422).json({ success: false, error: reason });
    }
    const catalog = Array.isArray(data.catalog) ? data.catalog : [];
    const entry = {
      key: meta.key,
      title: meta.title,
      thumb: meta.thumb,
      durationSec: meta.durationSec,
      genre: detectGenre(meta.title, meta.durationSec),
      vertical: meta.vertical === true,
      direct: meta.direct === true,
      akey: String(meta.akey || ''),
      views: 0,
      addedAt: Date.now(),
      ok: true,
    };
    await updateAdmin((fresh) => {
      fresh.catalog = Array.isArray(fresh.catalog) ? fresh.catalog : [];
      const at = fresh.catalog.findIndex((c) => c.key === entry.key);
      if (at >= 0) fresh.catalog[at] = entry;
      else fresh.catalog.unshift(entry);
      fresh.catalog = fresh.catalog.slice(0, 2000);
      const freshSugg = Array.isArray(fresh.suggestions)
        ? fresh.suggestions
        : [];
      const sAt = freshSugg.findIndex((s) => s.url === item.url);
      fresh.suggestions =
        sAt >= 0
          ? freshSugg.filter((_, i) => i !== sAt)
          : freshSugg.filter((_, i) => i !== idx);
    });
    res.json({ success: true, item: entry });
  } catch (error) {
    res.status(422).json({ success: false, error: 'unresolvable' });
  }
});

router.delete('/:idx', requireAdmin, async (req, res) => {
  try {
    const idx = Number(req.params.idx);
    await updateAdmin((data) => {
      const list = Array.isArray(data.suggestions)
        ? data.suggestions
        : [];
      data.suggestions = list.filter((_, i) => i !== idx);
    });
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: 'failed' });
  }
});

export default router;
