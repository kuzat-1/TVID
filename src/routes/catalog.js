import { Router } from 'express';
import { appendFileSync } from 'node:fs';
import { readAdmin, updateAdmin } from '../lib/adminDb.js';
import { resolveVkMeta } from '../services/vkParseService.js';

const router = Router();
const ADMIN_TOKEN =
  process.env.ADMIN_TOKEN || '123456tanho';

function requireAdmin(req, res, next) {
  const header = req.headers.authorization || '';
  if (header === `Bearer ${ADMIN_TOKEN}`) return next();
  return res
    .status(401)
    .json({ success: false, error: 'Unauthorized' });
}

const GENRE_WORDS = {
  film: ['фильм', 'фильмы', 'кино', 'movie', 'film'],
  serial: ['сериал', 'сериалы', 'серия', 'сезон'],
  music: ['музык', 'клип', 'песн', 'music', 'clip', 'концерт'],
  humor: ['юмор', 'смеш', 'комеди', 'прикол'],
  sport: ['спорт', 'sport'],
  show: ['шоу', 'show', 'передач'],
};

function queryGenres(q) {
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  const genres = new Set();
  for (const w of words) {
    for (const [genre, variants] of Object.entries(GENRE_WORDS)) {
      if (variants.some((v) => w.startsWith(v) || v.startsWith(w))) {
        genres.add(genre);
      }
    }
  }
  return genres;
}

function matchQuery(item, q) {
  if (!q) return true;
  const t = `${item.title || ''} ${item.key || ''}`.toLowerCase();
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.every((w) => t.includes(w))) return true;
  const genres = queryGenres(q);
  if (genres.size > 0 && item.genre && genres.has(item.genre)) {
    return true;
  }
  return false;
}

const MUSIC_WORDS = [
  'klip', 'clip', 'music', 'remix', 'song', 'mp3', 'konsert',
  'musiqa', 'qoshiq', 'qo‘shiq', 'ashula', 'trek',
  'концерт', 'клип', 'музыка', 'песня',
];
const SERIAL_WORDS = [
  'serial', 'qism', 'fasl', 'episode', 'серия', 'сезон', 'сериал',
];
const FILM_WORDS = [
  'kino', 'film', 'movie', 'tarjima', 'premera', 'multfilm',
  'kinozal', 'uzbekfilm', 'фильм', 'кино', 'премьера',
];
const HUMOR_WORDS = [
  'kulgu', 'hazil', 'prikol', 'comedy', 'standup', 'kulguli',
  'юмор', 'комедия', 'прикол',
];
const SPORT_WORDS = [
  'sport', 'futbol', 'boxing', 'mma', 'kurash', 'jangari', 'спорт',
];
const SHOW_WORDS = [
  'shou', 'show', 'dasturi', 'intervyu', 'podcast', 'ko‘rsatuv', 'шоу',
];
const LONG_FILM_SEC = 1800;

function hasAny(text, words) {
  return words.some((w) => text.includes(w));
}

export function detectGenre(title = '', durationSec = 0) {
  const t = title.toLowerCase();
  const dur = Number(durationSec) || 0;
  if (hasAny(t, MUSIC_WORDS)) return 'music';
  if (hasAny(t, SERIAL_WORDS)) return 'serial';
  if (hasAny(t, HUMOR_WORDS)) return 'humor';
  if (hasAny(t, SPORT_WORDS)) return 'sport';
  if (hasAny(t, SHOW_WORDS)) return 'show';
  if (dur >= LONG_FILM_SEC || hasAny(t, FILM_WORDS)) return 'film';
  return 'mix';
}

async function adminPassOk(req) {
  try {
    const data = await readAdmin();
    const pass = String(data.settings?.adminAppPass || '');
    const given = String(
      req.headers['x-admin-pass'] || req.body?.adminPass || ''
    );
    return pass.length >= 4 && given === pass;
  } catch {
    return false;
  }
}

router.post('/quick-add', async (req, res) => {
  if (!(await adminPassOk(req))) {
    return res
      .status(401)
      .json({ success: false, error: 'Unauthorized' });
  }
  try {
    const { resolveVkMeta } = await import(
      '../services/vkParseService.js'
    );
    const meta = await resolveVkMeta(
      String(req.body?.url || ''),
      20000
    );
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
      source: 'In-App Admin',
      sourceUrl: '',
      ok: true,
    };
    const total = await updateAdmin((data) => {
      const list = Array.isArray(data.catalog) ? data.catalog : [];
      const at = list.findIndex((c) => c.key === entry.key);
      if (at >= 0) list[at] = { ...list[at], ...entry };
      else list.unshift(entry);
      data.catalog = list.slice(0, 2000);
      return data.catalog.length;
    });
    res.json({ success: true, item: entry, total });
  } catch (error) {
    res.status(422).json({
      success: false,
      error: String(error.message || 'unresolvable').slice(0, 120),
    });
  }
});

router.get('/trends', async (req, res) => {
  try {
    diag.trendsHits = (diag.trendsHits || 0) + 1;
    const data = await readAdmin();
    const n = Math.min(
      Math.max(parseInt(req.query.limit, 10) || 25, 1),
      100
    );
    const items = (data.catalog || [])
      .filter((c) => !c.vertical)
      .slice(0, n);
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, items, total: items.length });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to read trends' });
  }
});

router.get('/reels', async (req, res) => {
  try {
    diag.reelsHits = (diag.reelsHits || 0) + 1;
    const data = await readAdmin();
    const verticals = (data.catalog || []).filter((c) => c.vertical);
    for (let i = verticals.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [verticals[i], verticals[j]] = [verticals[j], verticals[i]];
    }
    const limit = Math.min(
      Math.max(parseInt(req.query.limit, 10) || 200, 1),
      500
    );
    const items = verticals.slice(0, limit);
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, items, total: verticals.length });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to read reels' });
  }
});

router.get('/sources', async (req, res) => {
  try {
    const data = await readAdmin();
    const map = new Map();
    for (const c of data.catalog || []) {
      const name = c.source || 'Вручную';
      if (!map.has(name)) {
        map.set(name, {
          name,
          url: c.sourceUrl || '',
          count: 0,
          ok: 0,
          bad: 0,
        });
      }
      const s = map.get(name);
      s.count++;
      if (c.ok === false) s.bad++;
      else s.ok++;
    }
    res.json({ success: true, sources: [...map.values()] });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to read sources' });
  }
});

export const diag = { catalogHits: 0, catalogErrors: 0, streamHits: 0 };

router.get('/diag', async (req, res) => {
  res.json({ success: true, ...diag });
});

router.get('/', async (req, res) => {
  try {
    diag.catalogHits++;
    const data = await readAdmin();
    let q = String(req.query.q || '');
    const source = String(req.query.source || '');
    let sort = String(req.query.sort || '');
    if (q === 'new') {
      sort = 'new';
      q = '';
    } else if (q === 'popular') {
      sort = 'popular';
      q = '';
    }
    const period = String(req.query.period || 'week');
    let limit = Math.min(
      Math.max(parseInt(req.query.limit, 10) || 50, 1),
      100
    );
    if (!q && limit > 50) limit = 50;
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
    let matched = (data.catalog || []).filter(
      (c) =>
        (!source || (c.source || 'Вручную') === source) &&
        matchQuery(c, q)
    );
    if (q === '' && !source) {
      matched = matched.filter((c) => !c.vertical);
    }
    if (sort === 'new') {
      matched.sort((a, b) => (b.addedAt || 0) - (a.addedAt || 0));
    } else if (sort === 'popular') {
      if (period === 'month') {
        matched.sort((a, b) => (b.views || 0) - (a.views || 0));
      } else {
        matched.sort((a, b) => (b.views || 0) - (a.views || 0));
      }
    }
    const t0 = Date.now();
    res.on('finish', () => {
      try {
        appendFileSync(
          'logs/catalog-req.log',
          `${new Date().toISOString()} q=${q.slice(0, 40)} limit=${limit} offset=${offset} matched=${matched.length} status=${res.statusCode} ms=${Date.now() - t0} ip=${
            req.headers['cf-connecting-ip'] ||
            req.headers['x-forwarded-for']?.toString().split(',')[0].trim() ||
            req.ip
          }\n`
        );
      } catch {}
    });
    const items = matched.slice(offset, offset + limit);
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, items, total: matched.length });
  } catch (error) {
    diag.catalogErrors++;
    res
      .status(500)
      .json({ success: false, error: 'Failed to read catalog' });
  }
});

router.post('/resolve', requireAdmin, async (req, res) => {
  try {
    const meta = await resolveVkMeta(req.body?.url || req.body?.key || '');
    res.json({ success: true, ...meta });
  } catch (error) {
    res.status(422).json({ success: false, error: 'unresolvable video' });
  }
});

router.post('/', requireAdmin, async (req, res) => {
  try {
    const item = req.body || {};
    if (!item.key || !/(-?\d+)_(\d+)/.test(String(item.key))) {
      return res
        .status(400)
        .json({ success: false, error: 'bad key' });
    }
    const total = await updateAdmin((data) => {
      const list = Array.isArray(data.catalog) ? data.catalog : [];
      const idx = list.findIndex((c) => c.key === item.key);
      const prev =
        list.find((c) => c.key === String(item.key)) || {};
      const entry = {
        key: String(item.key),
        title: String(item.title || prev.title || 'Без названия'),
        thumb: String(item.thumb || prev.thumb || ''),
        durationSec: Number(item.durationSec) || Number(prev.durationSec) || 0,
        genre: String(
          item.genre ||
            prev.genre ||
            detectGenre(
              String(item.title || ''),
              Number(item.durationSec) || Number(prev.durationSec) || 0
            )
        ),
        vertical: item.vertical === true || prev.vertical === true,
        addedAt: Number(item.addedAt) || Number(prev.addedAt) || Date.now(),
        views: Number(item.views) || Number(prev.views) || 0,
        direct: item.direct === true || prev.direct === true,
        akey: String(item.akey || prev.akey || ''),
        source: String(item.source || prev.source || ''),
        sourceUrl: String(item.sourceUrl || prev.sourceUrl || ''),
        ok: item.ok === false ? false : prev.ok !== false,
      };
      if (idx >= 0) list[idx] = entry;
      else list.unshift(entry);
      data.catalog = list.slice(0, 2000);
      return { total: data.catalog.length, entry };
    });
    res.json({ success: true, item: total.entry, total: total.total });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to save catalog' });
  }
});

router.delete('/:key', requireAdmin, async (req, res) => {
  try {
    const total = await updateAdmin((data) => {
      data.catalog = (data.catalog || []).filter(
        (c) => c.key !== req.params.key
      );
      return data.catalog.length;
    });
    res.json({ success: true, total });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to delete' });
  }
});

export default router;
