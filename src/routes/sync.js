import { Router } from 'express';
import axios from 'axios';
import { execFile } from 'node:child_process';
import { readAdmin, updateAdmin } from '../lib/adminDb.js';
import { logSync } from '../lib/syncLog.js';
import { resolveVkMeta, cookieArgs } from '../services/vkParseService.js';
import { detectGenre } from './catalog.js';

const router = Router();
const ADMIN_TOKEN =
  process.env.ADMIN_TOKEN || '123456tanho';
const YTDLP = process.env.YT_DLP_PATH || 'yt-dlp';
const MAX_NEW_PER_SYNC = 100;
const nap = (ms) => new Promise((r) => setTimeout(r, ms));
const VK_API = 'https://api.vk.com/method';
const VK_V = '5.131';

function requireAdmin(req, res, next) {
  const header = req.headers.authorization || '';
  if (header === `Bearer ${ADMIN_TOKEN}`) return next();
  return res
    .status(401)
    .json({ success: false, error: 'Unauthorized' });
}

function runYtDlp(args, timeoutMs = 60000) {
  return new Promise((resolve, reject) => {
    execFile(
      YTDLP,
      [...args, '--no-playlist', '-q', ...cookieArgs()],
      { timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 },
      (error, stdout, stderr) => {
        if (error) {
          reject(new Error(String(stderr || error.message).slice(0, 200)));
          return;
        }
        resolve(String(stdout || ''));
      }
    );
  });
}

async function vkCall(method, params, token) {
  const resp = await axios.get(`${VK_API}/${method}`, {
    params: { ...params, access_token: token, v: VK_V },
    timeout: 15000,
    validateStatus: (s) => s === 200,
  });
  const data = resp.data;
  if (!data || data.error) {
    throw new Error(data?.error?.error_msg || 'vk error');
  }
  return data.response;
}

function isPolitical(title = '', desc = '') {
  const t = `${title} ${desc}`.toLowerCase();
  const words = [
    'политик', 'новости', 'новость', 'выборы', 'президент',
    'правительство', 'война', 'митинг', 'чиновник', 'депутат',
    'парламент', 'протест', 'революц', 'министр', 'путин',
    'зеленский', 'байден', 'трамп', 'навальн', 'мобилизац',
    'референдум', 'партия', 'politic', 'election', 'president',
    'government', 'war', 'protest', 'siyosat', 'prezident',
    'urush', 'saylov', 'miting',
  ];
  return words.some((w) => t.includes(w));
}

function mapVkItem(it, requirePlayer = true) {
  if (!it || typeof it !== 'object') return null;
  if (requirePlayer && (!it.player || typeof it.player !== 'string')) {
    return null;
  }
  if (it.content_restricted || it.is_private || it.adult) return null;
  const title = String(it.title || 'Без названия');
  if (isPolitical(title, String(it.description || ''))) return null;
  const frames = Array.isArray(it.first_frame) ? it.first_frame : [];
  const thumb = frames.length ? String(frames[frames.length - 1].url || '') : String(it.photo_800 || it.photo_320 || '');
  const durationSec = Number(it.duration) > 0 ? Math.round(Number(it.duration)) : 0;
  const w = Number(it.width) || 0;
  const h = Number(it.height) || 0;
  const key = `${it.owner_id}_${it.id}`;
  return {
    key,
    title,
    thumb,
    durationSec,
    genre: detectGenre(title, durationSec),
    vertical: h > 0 && w > 0 ? h > w : false,
    akey: typeof it.access_key === 'string' ? it.access_key : '',
    views: Number(it.views) || 0,
    addedAt: Date.now(),
    ok: true,
  };
}

router.post('/', requireAdmin, async (req, res) => {
  const url = String(req.body?.url || '').trim().slice(0, 300);
  const svcToken = String(req.body?.serviceToken || '').trim();
  if (!/^https?:\/\//.test(url) && !/^-?\d+$/.test(url)) {
    return res
      .status(400)
      .json({ success: false, error: 'need vk link' });
  }

  try {
    const data = await readAdmin();
    const catalog = Array.isArray(data.catalog) ? data.catalog : [];
    const known = new Set(catalog.map((c) => c.key));
    const token = svcToken || process.env.VK_SERVICE_TOKEN || '';

    let entries = [];
    let sourceName = '';
    let sourceUrl = url;

    const singleMatch = url.match(/(-?\d+)_(\d+)/);
    const ownerOnlyMatch = url.trim().match(/^(-?\d+)$/);
    const isPlaylist =
      /playlist/i.test(url) ||
      (/videos?[-_]?(\?|$)/i.test(url) && !singleMatch);
    const handleMatch =
      url.match(/@([a-zA-Z0-9_.]+)/) ||
      url.match(/vk(?:video)?\.(?:com|ru)\/([a-zA-Z0-9_.]+)/);

    if ((!isPlaylist && handleMatch && !singleMatch) || ownerOnlyMatch) {
      if (!token) {
        return res.status(400).json({
          success: false,
          error: 'need service token for channels',
        });
      }
      let g = {};
      let handle = '';
      if (ownerOnlyMatch) {
        handle = ownerOnlyMatch[1];
        const groups = await vkCall(
          'groups.getById',
          { group_id: Math.abs(Number(handle)) },
          token
        );
        g = (Array.isArray(groups) ? groups[0] : groups) || {};
      } else {
        handle = handleMatch[1].replace(/^(video|videos|clip|clips)$/i, '');
        const groups = await vkCall('groups.getById', { group_id: handle }, token);
        g = (Array.isArray(groups) ? groups[0] : groups) || {};
      }
      if (!g.id) {
        return res
          .status(422)
          .json({ success: false, error: 'channel not found' });
      }
      sourceName = String(g.name || handle).slice(0, 120);
      const ownerId = `-${g.id}`;
      let offset = 0;
      const total = [];
      for (let page = 0; page < 3; page++) {
        try {
          const resp = await vkCall(
            'video.get',
            { owner_id: ownerId, count: 200, offset, extended: 0 },
            token
          );
          const items = resp.items || [];
          if (!items.length) break;
          total.push(...items);
          offset += items.length;
          if (offset >= (resp.count || 0) || total.length >= 400) break;
        } catch {
          break;
        }
        await nap(400);
      }
      let wallOffset = 0;
      for (let page = 0; page < 3; page++) {
        try {
          const wresp = await vkCall(
            'wall.get',
            { owner_id: ownerId, count: 100, offset: wallOffset, filter: 'video' },
            token
          );
          const posts = wresp.items || [];
          if (!posts.length) break;
          for (const p of posts) {
            for (const a of p.attachments || []) {
              if (a.type === 'video' && a.video) {
                a.video.fromWall = true;
                total.push(a.video);
              }
            }
          }
          wallOffset += posts.length;
          if (wallOffset >= (wresp.count || 0) || total.length >= 700) break;
        } catch {
          break;
        }
        await nap(400);
      }
      for (const it of total) {
        const e = mapVkItem(it, !it.fromWall);
        if (e) entries.push(e);
      }
      const clipUrls = [];
      if (g.screen_name) {
        clipUrls.push(`https://vkvideo.ru/@${g.screen_name}`);
      }
      clipUrls.push(`https://vk.com/clips/${ownerId}`);
      for (const cu of clipUrls) {
        try {
          const raw = await runYtDlp(
            ['-J', '--flat-playlist', '--no-warnings', cu],
            60000
          );
          const d = JSON.parse(raw);
          for (const e of d.entries || []) {
            const id = String(e.id || '');
            if (/^-?\d+_\d+$/.test(id)) {
              try {
                const meta = await resolveVkMeta(id, 15000);
                entries.push({
                  key: meta.key,
                  title: meta.title,
                  thumb: meta.thumb,
                  durationSec: meta.durationSec,
                  genre: detectGenre(meta.title),
                  vertical: true,
                  direct: meta.direct === true,
                  akey: String(meta.akey || ''),
                  ok: true,
                });
              } catch {}
            }
          }
        } catch {}
      }
    } else if (isPlaylist) {
      const flatIds = [];
      const normUrl = url
        .replace(/https?:\/\/(m\.)?vkvideo\.ru\//, 'https://vk.com/')
        .replace(/https?:\/\/vk\.ru\//, 'https://vk.com/')
        .replace(/\/clip(-?\d+_\d+)/, '/video$1');
      const plMatch = normUrl.match(/playlist\/(-?\d+)_(\d+)/);
      if (plMatch && token) {
        try {
          const albums = await vkCall(
            'video.getAlbums',
            { owner_id: plMatch[1], extended: 0 },
            token
          );
          const alb = (albums.items || []).find(
            (a) => String(a.id) === plMatch[2]
          );
          if (alb && alb.title) {
            sourceName = String(alb.title).slice(0, 120);
          }
        } catch {}
        let offset = 0;
        const total = [];
        for (let page = 0; page < 3; page++) {
          try {
            const resp = await vkCall(
              'video.get',
              {
                owner_id: plMatch[1],
                album_id: plMatch[2],
                count: 200,
                offset,
                extended: 0,
              },
              token
            );
            const items = resp.items || [];
            if (!items.length) break;
            total.push(...items);
            offset += items.length;
            if (offset >= (resp.count || 0) || total.length >= 400) break;
          } catch {
            break;
          }
          await nap(400);
        }
        for (const it of total) {
          const e = mapVkItem(it);
          if (e) entries.push(e);
        }
        if (!sourceName) sourceName = 'Плейлист';
      } else {
        const raw = await runYtDlp([
          '-J',
          '--flat-playlist',
          '--no-warnings',
          normUrl,
        ]);
        let d = {};
        try {
          d = JSON.parse(raw);
        } catch {
          return res
            .status(422)
            .json({ success: false, error: 'playlist unreadable' });
        }
        sourceName = String(d.title || 'Плейлист').slice(0, 120);
        for (const e of d.entries || []) {
          flatIds.push(String(e.id || ''));
        }
      }
      const ids = [];
      for (const rawId of flatIds) {
        if (/^-?\d+_\d+$/.test(rawId) && !ids.includes(rawId)) {
          ids.push(rawId);
        }
      }
      for (const key of ids) {
        const [oid, vid] = key.split('_');
        try {
          const resp = await vkCall(
            'video.get',
            { videos: `${oid}_${vid}`, extended: 0 },
            token || undefined
          );
          const items = resp.items || [];
          const e = mapVkItem(items[0]);
          if (e) entries.push(e);
        } catch {}
      }
      if (!entries.length && ids.length) {
        for (const key of ids.slice(0, MAX_NEW_PER_SYNC)) {
          try {
            const meta = await resolveVkMeta(key, 15000);
            entries.push({
              key: meta.key,
              title: meta.title,
              thumb: meta.thumb,
              durationSec: meta.durationSec,
              genre: detectGenre(meta.title, meta.durationSec),
              vertical: meta.vertical === true,
              direct: meta.direct === true,
              views: 0,
              addedAt: Date.now(),
              ok: true,
            });
          } catch {}
        }
      }
    } else if (singleMatch) {
      const key = `${singleMatch[1]}_${singleMatch[2]}`;
      try {
        const resp = await vkCall(
          'video.get',
          { videos: key, extended: 0 },
          token || undefined
        );
        const e = mapVkItem((resp.items || [])[0]);
        if (e) entries.push(e);
      } catch {}
      if (!entries.length) {
        try {
          const meta = await resolveVkMeta(key, 15000);
          entries.push({
            key: meta.key,
            title: meta.title,
            thumb: meta.thumb,
            durationSec: meta.durationSec,
            genre: detectGenre(meta.title, meta.durationSec),
            vertical: meta.vertical === true,
            direct: meta.direct === true,
            akey: String(meta.akey || ''),
            ok: true,
          });
        } catch {}
      }
    } else {
      return res
        .status(422)
        .json({ success: false, error: 'nothing found by link' });
    }

    if (!sourceName) {
      sourceName = url.replace(/^https?:\/\//, '').slice(0, 80);
    }
    const freshEntries = entries.filter(
      (e) => e && typeof e.key === 'string' && e.key.includes('_')
    );
    if (!freshEntries.length) {
      console.log(
        `[sync] ${sourceName}: fetched=0 — keeping existing catalog untouched`
      );
      logSync({
        source: sourceName,
        existing: catalog.length,
        fetched: 0,
        added: 0,
        updated: 0,
        final: catalog.length,
        ok: false,
        note: 'empty fetch, catalog untouched',
      });
      return res.json({
        success: true,
        found: 0,
        added: 0,
        skipped: 0,
        verticals: 0,
        source: sourceName,
        note: 'empty fetch, catalog untouched',
      });
    }
    if (freshEntries.length < 3 && catalog.length > 50) {
      console.log(
        `[sync] ${sourceName}: suspiciously small fetch (${freshEntries.length}) vs existing ${catalog.length} — merging anyway, nothing removed`
      );
    }
    let added = 0;
    let skipped = 0;
    for (const e of freshEntries) {
      if (known.has(e.key)) {
        skipped++;
      }
    }
    const verticals = freshEntries.filter(
      (e, i, arr) =>
        e.vertical && arr.findIndex((x) => x.key === e.key) === i
    ).length;
    const finalCount = await updateAdmin((fresh) => {
      const list = Array.isArray(fresh.catalog) ? fresh.catalog : [];
      const freshKnown = new Set(list.map((c) => c.key));
      let n = 0;
      for (const e of freshEntries) {
        if (freshKnown.has(e.key)) continue;
        freshKnown.add(e.key);
        list.unshift({
          ...e,
          source: sourceName,
          sourceUrl: url,
        });
        n++;
      }
      fresh.catalog = list.slice(0, 2000);
      return { final: fresh.catalog.length, added: n };
    });
    added = finalCount.added;
    const finalTotal = finalCount.final;
    console.log(
      `[sync] ${sourceName}: existing=${catalog.length} fetched=${freshEntries.length} added=${added} skipped=${skipped} final=${finalTotal}`
    );
    logSync({
      source: sourceName,
      existing: catalog.length,
      fetched: freshEntries.length,
      added,
      updated: 0,
      final: finalTotal,
      ok: true,
    });
    res.json({
      success: true,
      found: entries.length,
      added,
      skipped,
      verticals,
      source: sourceName,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: 'sync failed' });
  }
});

export default router;
