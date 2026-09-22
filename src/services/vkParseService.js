import { execFile } from 'node:child_process';
import axios from 'axios';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const COOKIE_FILE = path.join(__dirname, '..', '..', 'data', 'vk_cookies.txt');

export function cookieArgs() {
  try {
    fs.accessSync(COOKIE_FILE);
    return ['--cookies', COOKIE_FILE];
  } catch {
    return [];
  }
}

const MAX_CACHE_MS = 8 * 60 * 60 * 1000;
const MIN_CACHE_MS = 5 * 60 * 1000;
const DEFAULT_TTL_HOURS = 6;
let cacheTtlMs = DEFAULT_TTL_HOURS * 60 * 60 * 1000;
const cache = new Map();
const YTDLP = process.env.YT_DLP_PATH || 'yt-dlp';

export function setCacheTtlHours(hours) {
  const h = Number(hours);
  if (Number.isFinite(h) && h >= 1 && h <= 72) {
    cacheTtlMs = h * 60 * 60 * 1000;
  }
  return cacheTtlMs / 3600000;
}

export function getCacheInfo() {
  return { size: cache.size, ttlHours: cacheTtlMs / 3600000 };
}

export function clearCache() {
  const size = cache.size;
  cache.clear();
  return { cleared: true, size };
}

function runYtDlp(args, timeoutMs = 25000) {
  return new Promise((resolve, reject) => {
    execFile(
      YTDLP,
      [...args, '--no-playlist', '-q', ...cookieArgs()],
      { timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 },
      (error, stdout, stderr) => {
        if (error) {
          reject(new Error(String(stderr || error.message).slice(0, 300)));
          return;
        }
        resolve(String(stdout || ''));
      }
    );
  });
}

async function validateThumb(url) {
  if (!url || !/^https?:\/\//.test(url)) return false;
  try {
    const resp = await axios.head(url, { timeout: 5000, validateStatus: s => s === 200 });
    const ct = resp.headers['content-type'] || '';
    return ct.startsWith('image/');
  } catch {
    return false;
  }
}

async function pickWorkingThumb(thumbs) {
  for (const t of thumbs) {
    if (await validateThumb(t)) return t;
  }
  return '';
}

function firstHttpUrl(text) {
  for (const line of text.split('\n')) {
    const t = line.trim();
    if (/^https?:\/\//.test(t)) return t;
  }
  return '';
}

function ttlForUrl(url) {
  try {
    const m = url.match(/[?&]expires=(\d+)/);
    if (m) {
      const left = Number(m[1]) - Date.now() - 5 * 60 * 1000;
      if (Number.isFinite(left) && left > 0) {
        return Math.min(left, MAX_CACHE_MS);
      }
      return MIN_CACHE_MS;
    }
  } catch {}
  return MAX_CACHE_MS;
}

export function vkWatchUrl(oid, id) {
  return `https://vk.com/video${oid}_${id}`;
}

export async function getVkDirectUrl(oid, id, hash = '', ttlOverrideMs = 0) {
  const key = `${oid}_${id}`;
  const now = Date.now();
  const ttl = ttlOverrideMs > 0 ? ttlOverrideMs : cacheTtlMs;
  const hit = cache.get(`stream:${key}`);
  if (hit && now - hit.ts < ttl) {
    return { ...hit.data, cached: true };
  }
  const url = await runYtDlp(['-g', vkWatchUrl(oid, id)]).then(firstHttpUrl);
  if (!url) {
    return { success: false, error: 'no playable url', videoKey: key };
  }
  const data = {
    success: true,
    url,
    quality: /\.m3u8(\?|$)/.test(url) ? 'hls' : 'mp4',
    videoKey: key,
  };
  const entryTtl = Math.min(ttlForUrl(url), ttl);
  cache.set(`stream:${key}`, {
    ts: now,
    ttl: entryTtl,
    data,
  });
  if (cache.size > 500) {
    const first = cache.keys().next().value;
    cache.delete(first);
  }
  return { ...data, cached: false };
}

export async function resolveVkMeta(input, timeoutMs = 30000) {
  let url = String(input || '').trim();
  const m = url.match(/(-?\d+)_(\d+)/);
  if (!m) {
    throw new Error('bad video key or url');
  }
  const key = `${m[1]}_${m[2]}`;
  url = url.replace(/\/clip(-?\d+_\d+)/, '/video$1');
  if (!/^https?:\/\//.test(url)) {
    url = vkWatchUrl(m[1], m[2]);
  }
  const svc = process.env.VK_SERVICE_TOKEN || '';
  let noEmbed = false;
  if (svc) {
    try {
      const resp = await axios.get('https://api.vk.com/method/video.get', {
        params: { videos: key, access_token: svc, v: '5.131' },
        timeout: 10000,
        validateStatus: (s) => s === 200,
      });
      const it = resp.data?.response?.items?.[0];
      if (it && !it.player) {
        const frames = Array.isArray(it.first_frame) ? it.first_frame : [];
        const thumbUrls = frames.map(f => String(f.url || '')).filter(Boolean);
        const thumb = thumbUrls.length ? await pickWorkingThumb(thumbUrls) : '';
        const dur = Number(it.duration) > 0 ? Math.round(Number(it.duration)) : 0;
        const w = Number(it.width) || 0;
        const h = Number(it.height) || 0;
        const desc = String(it.description || '').split('\n')[0].slice(0, 120);
        return {
          key,
          title: String(it.title || desc || 'Клип'),
          thumb,
          durationSec: dur,
          vertical: h > 0 && w > 0 ? h > w : false,
          direct: true,
        };
      }
      if (it && it.player) {
        const frames = Array.isArray(it.first_frame) ? it.first_frame : [];
        const thumbUrls = frames.map(f => String(f.url || '')).filter(Boolean);
        const thumb = thumbUrls.length ? await pickWorkingThumb(thumbUrls) : '';
        const dur = Number(it.duration) > 0 ? Math.round(Number(it.duration)) : 0;
        const w = Number(it.width) || 0;
        const h = Number(it.height) || 0;
        return {
          key,
          title: String(it.title || 'Без названия'),
          thumb,
          durationSec: dur,
          vertical: h > 0 && w > 0 ? h > w : false,
          akey: typeof it.access_key === 'string' ? it.access_key : '',
        };
      }
    } catch {}
  }
  try {
    const raw = await runYtDlp(
      ['--dump-json', '--skip-download', url],
      timeoutMs
    );
    const d = JSON.parse(raw);
    const title = String(d.title || 'Без названия');
    const thumbs = [];
    if (d.thumbnail) thumbs.push(String(d.thumbnail));
    if (Array.isArray(d.thumbnails)) {
      for (const t of d.thumbnails) {
        if (t.url) thumbs.push(String(t.url));
      }
    }
    const thumb = thumbs.length ? await pickWorkingThumb(thumbs) : '';
    const durationSec =
      Number.isFinite(Number(d.duration)) && Number(d.duration) > 0
        ? Math.round(Number(d.duration))
        : 0;
    const w = Number(d.width) || 0;
    const h = Number(d.height) || 0;
    return {
      key,
      title,
      thumb,
      durationSec,
      vertical: h > 0 && w > 0 ? h > w : false,
      direct: noEmbed,
    };
  } catch (_) {
    if (noEmbed) throw new Error('no_player');
    throw new Error('unresolvable');
  }
}
