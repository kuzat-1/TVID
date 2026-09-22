import express from 'express';
import cors from 'cors';
import compression from 'compression';
import axios from 'axios';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import 'dotenv/config';
import vkRoutes from './routes/vk.js';
import youtubeRoutes from './routes/youtube.js';
import adminRoutes from './routes/admin.js';
import streamVkRoutes from './routes/streamVk.js';
import catalogRoutes from './routes/catalog.js';
import suggestRoutes from './routes/suggest.js';
import syncRoutes from './routes/sync.js';
import { startAutoCrawl } from './lib/autoCrawl.js';
import { startScheduledSync } from './lib/scheduledSync.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.BACKEND_PORT || 3000;

app.use(cors());
app.use(compression({ level: 6, threshold: 1024 }));
app.use(express.json());

app.use('/api/vk', vkRoutes);
app.use('/api/yt', youtubeRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/stream-vk', streamVkRoutes);
app.use('/api/catalog', catalogRoutes);
app.use('/api/suggest', suggestRoutes);
app.use('/api/sync', syncRoutes);

app.get('/api/thumb', async (req, res) => {
  try {
    const u = String(req.query.url || '');
    if (!/^https:\/\/(sun|iv|pp|ps|vk)\S+\.(userapi\.com|okcdn\.ru|vk\.com|vkvideo\.ru)\/\S+/.test(u) &&
        !/^https:\/\/i\.ytimg\.com\//.test(u)) {
      return res.status(400).json({ success: false });
    }
    const r = await axios.get(u, {
      responseType: 'arraybuffer',
      timeout: 15000,
      maxContentLength: 2 * 1024 * 1024,
      headers: { 'User-Agent': 'Mozilla/5.0' },
      validateStatus: (s) => s === 200,
    });
    const ct = String(r.headers['content-type'] || 'image/jpeg');
    res.set('Content-Type', ct.split(';')[0]);
    res.set('Cache-Control', 'public, max-age=86400');
    res.send(Buffer.from(r.data));
  } catch (error) {
    res.status(502).json({ success: false });
  }
});

app.use(express.static(path.join(__dirname, '..', 'public')));

app.get(['/privacy', '/dmca'], (req, res) => {
  const file =
    req.path === '/privacy' ? 'privacy.html' : 'dmca.html';
  res.sendFile(path.join(__dirname, '..', 'public', file));
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

const EXTRA_PORTS = [8080, 8000];
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Stream backend running on port ${PORT}`);
  for (const p of EXTRA_PORTS) {
    try {
      app.listen(p, '0.0.0.0', () => {
        console.log(`Mirror running on port ${p}`);
      });
    } catch (e) {
      console.error(`Port ${p} busy:`, e.message);
    }
  }
  console.log(`Endpoints:`);
  console.log(`  GET /api/vk/stream?oid=<owner_id>&id=<video_id>[&hash=<hash>]`);
  console.log(`  GET /api/yt/stream?v=<video_id>`);
  console.log(`  GET /api/admin/config`);
  console.log(`  GET /admin/ (web admin panel)`);
  console.log(`  GET /health`);
  try {
    startAutoCrawl();
  } catch (error) {
    console.error('autocrawl disabled:', error.message);
  }
  try {
    startScheduledSync();
  } catch (error) {
    console.error('scheduled sync disabled:', error.message);
  }
});

export default app;