import { Router } from 'express';
import {
  getVkDirectUrl,
  setCacheTtlHours,
  getCacheInfo,
  clearCache,
} from '../services/vkParseService.js';
import { readAdmin } from '../lib/adminDb.js';

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

async function currentTtlMs() {
  try {
    const data = await readAdmin();
    const h = Number(data.settings?.cacheTtlHours) || 6;
    return setCacheTtlHours(h) * 3600000;
  } catch {
    return 0;
  }
}

router.get('/cache', requireAdmin, async (req, res) => {
  try {
    await currentTtlMs();
    res.json({ success: true, ...getCacheInfo() });
  } catch (error) {
    res.status(500).json({ success: false, error: 'cache error' });
  }
});

router.delete('/cache', requireAdmin, async (req, res) => {
  try {
    res.json({ success: true, ...clearCache() });
  } catch (error) {
    res.status(500).json({ success: false, error: 'cache error' });
  }
});

router.get('/', async (req, res) => {
  const started = Date.now();
  const { oid, id, hash = '', rawId = '' } = req.query;

  let o = oid;
  let v = id;
  if ((!o || !v) && rawId) {
    const m = String(rawId).match(/(-?\d+)_(\d+)/);
    if (m) {
      o = m[1];
      v = m[2];
    }
  }
  if (!o || !v) {
    return res.status(400).json({
      success: false,
      error: 'Missing oid+id (or rawId like -12345_67890)',
    });
  }

  try {
    const { diag } = await import('./catalog.js');
    diag.streamHits++;
    const ttl = await currentTtlMs();
    const result = await getVkDirectUrl(
      String(o),
      String(v),
      String(hash),
      ttl
    );
    res.json({ ...result, elapsedMs: Date.now() - started });
  } catch (error) {
    res.status(500).json({ success: false, error: 'parse failed' });
  }
});

export default router;
