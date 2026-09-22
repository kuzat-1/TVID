import { execFile } from 'child_process';
import 'dotenv/config';

const YT_DLP_PATH = process.env.YT_DLP_PATH || 'yt-dlp';
const VK_USER_AGENT = process.env.VK_USER_AGENT || 'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

function runYtDlpVk(oid, id, hash = null) {
  return new Promise((resolve, reject) => {
    const baseUrl = `https://vk.com/video${oid}_${id}`;
    const url = hash ? `${baseUrl}?hash=${hash}` : baseUrl;
    
    // Force IPv4 with -4 flag, skip SSL verification
    const args = ['-4', '-g', '-f', 'best', '--no-check-certificate', url];
    
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
        // Prefer video URLs (not audio-only)
        const videoUrls = urls.filter(u => 
          u.includes('googlevideo.com') || 
          u.includes('vk.com/video') || 
          u.includes('.m3u8') || 
          u.includes('.mp4')
        );
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

export async function getVkStreamUrl(oid, id, hash = null) {
  const urls = await runYtDlpVk(oid, id, hash);
  
  if (!urls.length) {
    throw new Error('No stream URLs found from VK via yt-dlp');
  }
  
  return {
    stream_url: urls[0],
    headers: {
      'Referer': 'https://vk.com/',
      'User-Agent': VK_USER_AGENT
    }
  };
}