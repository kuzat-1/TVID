import { execFile } from 'child_process';
import 'dotenv/config';

const YT_DLP_PATH = process.env.YT_DLP_PATH || 'yt-dlp';

function runYtDlp(videoId) {
  return new Promise((resolve, reject) => {
    const url = `https://www.youtube.com/watch?v=${videoId}`;
    // Don't specify format - let yt-dlp return all available URLs
    // We'll pick the first video URL (not audio-only)
    const args = ['-g', '--no-check-certificate', url];
    
    const child = execFile(YT_DLP_PATH, args, {
      env: { ...process.env, PATH: process.env.PATH + ':/home/opencode/.deno/bin' },
      timeout: 60000,
      maxBuffer: 1024 * 1024 * 10
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
        // Filter to prefer video URLs (not audio-only)
        const videoUrls = urls.filter(u => u.includes('googlevideo.com') && (u.includes('itag=401') || u.includes('itag=248') || u.includes('itag=137') || u.includes('itag=299') || u.includes('itag=399')));
        resolve(videoUrls.length > 0 ? videoUrls : urls);
      } else {
        reject(new Error(stderr || `yt-dlp exited with code ${code}`));
      }
    });
    
    child.on('error', (err) => {
      reject(err);
    });
  });
}

export async function getYtStreamUrl(videoId) {
  const urls = await runYtDlp(videoId);
  
  if (!urls.length) {
    throw new Error('No stream URLs found');
  }
  
  return {
    stream_url: urls[0],
    headers: {
      'Referer': 'https://www.youtube.com/',
      'User-Agent': process.env.VK_USER_AGENT || 'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
    }
  };
}