import { Router } from 'express';
import {
  readAdmin,
  updateAdmin,
  publicConfig,
  statsView,
} from '../lib/adminDb.js';
import { setCacheTtlHours } from '../services/vkParseService.js';

const router = Router();
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || '123456tanho';
const MAX_FAILS = 3;
const BLOCK_MS = 24 * 60 * 60 * 1000;

function clientIp(req) {
  return (
    req.headers['cf-connecting-ip'] ||
    req.headers['x-forwarded-for']?.toString().split(',')[0].trim() ||
    req.ip ||
    'unknown'
  );
}

function pruneFails(fails) {
  const now = Date.now();
  for (const [ip, rec] of Object.entries(fails)) {
    if (!rec || now - (rec.firstFail || 0) > BLOCK_MS) {
      delete fails[ip];
    }
  }
}

async function checkBlocked(req, res) {
  const blocked = await updateAdmin((data) => {
    pruneFails(data.authFails);
    const rec = data.authFails[clientIp(req)];
    if (rec && rec.count >= MAX_FAILS) {
      const retryAfter = Math.max(
        0,
        Math.ceil((rec.blockedUntil - Date.now()) / 1000)
      );
      if (Date.now() < rec.blockedUntil) {
        return { blocked: true, retryAfter };
      }
    }
    return { blocked: false, retryAfter: 0 };
  });
  if (blocked.blocked) {
    res.status(403).json({
      success: false,
      error: 'blocked',
      retryAfter: blocked.retryAfter,
    });
    return true;
  }
  return false;
}

async function registerFail(req) {
  try {
    return await updateAdmin((data) => {
      pruneFails(data.authFails);
      const ip = clientIp(req);
      const rec = data.authFails[ip] || { count: 0, firstFail: Date.now() };
      rec.count += 1;
      if (rec.count >= MAX_FAILS) {
        rec.blockedUntil = Date.now() + BLOCK_MS;
      }
      data.authFails[ip] = rec;
      return rec;
    });
  } catch {
    return { count: 0 };
  }
}

async function clearFails(req) {
  try {
    await updateAdmin((data) => {
      delete data.authFails[clientIp(req)];
    });
  } catch {}
}

function extractToken(req) {
  const header = req.headers.authorization || '';
  if (header.startsWith('Bearer ')) return header.slice(7);
  if (typeof req.body?.token === 'string') return req.body.token;
  return '';
}

async function tokenOk(req) {
  const t = extractToken(req);
  if (!t) return false;
  if (t === ADMIN_TOKEN) return true;
  try {
    const data = await readAdmin();
    const appPass = data.settings?.adminAppPass;
    return typeof appPass === 'string' && appPass.length >= 4 && t === appPass;
  } catch {
    return false;
  }
}

async function requireAdmin(req, res, next) {
  if (await checkBlocked(req, res)) return;
  if (await tokenOk(req)) {
    await clearFails(req);
    return next();
  }
  const rec = await registerFail(req);
  const left = Math.max(0, MAX_FAILS - rec.count);
  return res.status(401).json({
    success: false,
    error: 'Unauthorized',
    attemptsLeft: left,
  });
}

router.post('/login', async (req, res) => {
  if (await checkBlocked(req, res)) return;
  if (await tokenOk(req)) {
    await clearFails(req);
    return res.json({ success: true });
  }
  const rec = await registerFail(req);
  const left = Math.max(0, MAX_FAILS - rec.count);
  return res.status(rec.count >= MAX_FAILS ? 403 : 401).json({
    success: false,
    error: rec.count >= MAX_FAILS ? 'blocked' : 'Unauthorized',
    attemptsLeft: left,
    retryAfter: rec.count >= MAX_FAILS ? BLOCK_MS / 1000 : 0,
  });
});

router.get('/app_config.json', async (req, res) => {
  try {
    const data = await readAdmin();
    res.json({
      latest_version: data.settings.latestVersion || '1.0.0',
      min_required_version: data.settings.forceUpdate
        ? data.settings.latestVersion || '1.0.0'
        : '1.0.0',
      update_url:
        'https://play.google.com/store/apps/details?id=su.layn.app',
    });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to read config' });
  }
});

router.get('/config', async (req, res) => {
  try {
    const data = await readAdmin();
    res.json({ success: true, ...publicConfig(data) });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to read config' });
  }
});

router.get('/secrets', requireAdmin, async (req, res) => {
  try {
    const data = await readAdmin();
    res.json({
      success: true,
      vkToken: String(data.settings?.vkToken || ''),
      vkCookies: String(data.settings?.vkCookies || ''),
      adminAppPass: String(data.settings?.adminAppPass || ''),
    });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to read secrets' });
  }
});

router.post('/config', requireAdmin, async (req, res) => {
  try {
    const saved = await updateAdmin((data) => {
    const { blacklist, custom, settings } = req.body || {};
    if (Array.isArray(blacklist)) {
      data.blacklist = blacklist.map(String);
    }
    if (custom && typeof custom === 'object') {
      data.custom = custom;
    }
    if (settings && typeof settings === 'object') {
      const allowed = [
        'yandexEnabled',
        'feedAdEvery',
        'reelsAdEvery',
        'feedBlockId',
        'reelsBlockId',
        'latestVersion',
        'forceUpdate',
        'adminAppPass',
        'customHtmlEnabled',
        'customHtml',
        'customHtmlPlacement',
        'htmlPlayer',
        'htmlOpen',
        'htmlFeed',
        'htmlReels',
        'vkToken',
        'cacheTtlHours',
        'videoSource',
        'vkAppId',
        'playerAdMode',
        'playerAdEvery',
        'vkToken',
        'vkCookies',
      ];
      for (const key of allowed) {
        if (settings[key] !== undefined) {
          data.settings[key] = settings[key];
        }
      }
    }
      return {
        cacheTtlHours: data.settings.cacheTtlHours,
        vkCookies: String(data.settings.vkCookies || ''),
        snapshot: publicConfig(data),
      };
    });
    if (saved.cacheTtlHours !== undefined) {
      setCacheTtlHours(saved.cacheTtlHours);
    }
    try {
      const { COOKIE_FILE } = await import(
        '../services/vkParseService.js'
      );
      const { promises: fsp } = await import('node:fs');
      const { dirname } = await import('node:path');
      await fsp.mkdir(dirname(COOKIE_FILE), { recursive: true });
      const ck = saved.vkCookies.trim();
      if (ck) {
        await fsp.writeFile(COOKIE_FILE, ck, { mode: 0o600 });
      } else {
        await fsp.rm(COOKIE_FILE, { force: true });
      }
    } catch {}
    res.json({ success: true, ...saved.snapshot });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to save config' });
  }
});

router.post('/ads/report', async (req, res) => {
  try {
    await updateAdmin((data) => {
      const reports = Array.isArray(data.adReports) ? data.adReports : [];
      reports.unshift({
        ts: new Date().toISOString(),
        reason: String(req.body?.reason || 'report').slice(0, 200),
        ip:
          req.headers['cf-connecting-ip'] ||
          req.headers['x-forwarded-for']?.toString().split(',')[0].trim() ||
          req.ip ||
          'unknown',
      });
      data.adReports = reports.slice(0, 200);
    });
    res.json({ success: true });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to save report' });
  }
});

router.get('/stats', async (req, res) => {
  try {
    const data = await readAdmin();
    const today = new Date().toISOString().slice(0, 10);
    res.json({
      success: true,
      views: data.stats.views,
      viewsToday: data.stats.viewsByDay[today] || 0,
      blacklist: data.blacklist.length,
      customCount: Object.keys(data.custom).length,
      reports: Array.isArray(data.adReports) ? data.adReports.length : 0,
    });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to read stats' });
  }
});

router.post('/stats/view', async (req, res) => {
  try {
    const views = await updateAdmin((data) => {
      data.stats = statsView(data);
      return data.stats.views;
    });
    res.json({ success: true, views });
  } catch (error) {
    res
      .status(500)
      .json({ success: false, error: 'Failed to save stats' });
  }
});

export default router;
