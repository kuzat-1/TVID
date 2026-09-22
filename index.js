import express from 'express';
import cors from 'cors';
import axios from 'axios';
import * as cheerio from 'cheerio';
import { spawn } from 'child_process';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

const MOBILE_UA = 'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

function extractVkPlayerParams(html) {
  const $ = cheerio.load(html);
  
  const scripts = $('script').toArray();
  
  for (const script of scripts) {
    const content = $(script).html() || '';
    
    if (content.includes('playerParams')) {
      const match = content.match(/playerParams\s*=\s*(\{[\s\S]*?\});/);
      if (match) {
        try {
          return JSON.parse(match[1]);
        } catch (e) {
          const cleaned = match[1].replace(/\\/g, '');
          try {
            return JSON.parse(cleaned);
          } catch (e2) {
            continue;
          }
        }
      }
    }
  }
  
  return null;
}

function findBestQualityUrl(playerParams) {
  if (!playerParams) return null;
  
  const urls = [];
  
  if (playerParams.hls) {
    urls.push({ url: playerParams.hls, type: 'hls', quality: 'auto' });
  }
  
  if (playerParams.dash) {
    urls.push({ url: playerParams.dash, type: 'dash', quality: 'auto' });
  }
  
  if (playerParams.files) {
    for (const [quality, url] of Object.entries(playerParams.files)) {
      if (typeof url === 'string' && (url.includes('.m3u8') || url.includes('.mp4'))) {
        const qNum = parseInt(quality);
        if (!isNaN(qNum)) {
          urls.push({ url, type: url.includes('.m3u8') ? 'hls' : 'mp4', quality: qNum });
        }
      }
    }
  }
  
  urls.sort((a, b) => {
    if (a.type === 'hls' && b.type !== 'hls') return -1;
    if (b.type === 'hls' && a.type !== 'hls') return 1;
    return (b.quality || 0) - (a.quality || 0);
  });
  
  return urls[0]?.url || null;
}

app.get('/api/vk/stream', async (req, res) => {
  const { oid, id, hash } = req.query;
  
  if (!oid || !id) {
    return res.status(400).json({
      success: false,
      error: 'Missing required parameters: oid (owner_id) and id (video_id)'
    });
  }
  
  try {
    const vkUrl = `https://vk.com/video_ext.php?oid=${encodeURIComponent(oid)}&id=${encodeURIComponent(id)}${hash ? `&hash=${encodeURIComponent(hash)}` : ''}`;
    
    const response = await axios.get(vkUrl, {
      headers: {
        'User-Agent': MOBILE_UA,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
      },
      timeout: 15000,
      maxRedirects: 5
    });
    
    const playerParams = extractVkPlayerParams(response.data);
    const streamUrl = findBestQualityUrl(playerParams);
    
    if (!streamUrl) {
      return res.status(404).json({
        success: false,
        error: 'Could not extract stream URL from VK video page'
      });
    }
    
    res.json({
      success: true,
      provider: 'vk',
      hls_url: streamUrl,
      headers: {
        'Referer': 'https://vk.com/',
        'User-Agent': MOBILE_UA
      }
    });
    
  } catch (error) {
    console.error('VK stream error:', error.message);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch VK video',
      details: error.message
    });
  }
});

function runYtDlp(videoId) {
  return new Promise((resolve, reject) => {
    const url = `https://www.youtube.com/watch?v=${videoId}`;
    const args = ['-g', '-f', 'best[ext=mp4]/best', url];
    
    const child = spawn('yt-dlp', args, {
      env: { ...process.env, PATH: process.env.PATH }
    });
    
    let stdout = '';
    let stderr = '';
    
    child.stdout.on('data', (data) => {
      stdout += data.toString();
    });
    
    child.stderr.on('data', (data) => {
      stderr += data.toString();
    });
    
    child.on('close', (code) => {
      if (code === 0) {
        const urls = stdout.trim().split('\n').filter(Boolean);
        resolve(urls);
      } else {
        reject(new Error(stderr || `yt-dlp exited with code ${code}`));
      }
    });
    
    child.on('error', (err) => {
      reject(err);
    });
  });
}

app.get('/api/yt/stream', async (req, res) => {
  const { v } = req.query;
  
  if (!v) {
    return res.status(400).json({
      success: false,
      error: 'Missing required parameter: v (YouTube Video ID)'
    });
  }
  
  try {
    const urls = await runYtDlp(v);
    
    if (!urls.length) {
      return res.status(404).json({
        success: false,
        error: 'No stream URLs found'
      });
    }
    
    const streamUrl = urls[0];
    
    res.json({
      success: true,
      provider: 'youtube',
      stream_url: streamUrl,
      headers: {
        'Referer': 'https://www.youtube.com/',
        'User-Agent': MOBILE_UA
      }
    });
    
  } catch (error) {
    console.error('YouTube stream error:', error.message);
    res.status(500).json({
      success: false,
      error: 'Failed to extract YouTube stream',
      details: error.message
    });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Stream backend running on port ${PORT}`);
  console.log(`Endpoints:`);
  console.log(`  GET /api/vk/stream?oid=<owner_id>&id=<video_id>[&hash=<hash>]`);
  console.log(`  GET /api/yt/stream?v=<video_id>`);
  console.log(`  GET /health`);
});