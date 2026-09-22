const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 5102;
const FILE_DIR = '/home/opencode/projects/stream_app/build/app/outputs';

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  
  if (url.pathname === '/' || url.pathname === '/index.html') {
    // List files
    const bundleDir = path.join(FILE_DIR, 'bundle/release');
    const apkDir = path.join(FILE_DIR, 'flutter-apk');
    
    const files = [];
    if (fs.existsSync(bundleDir)) {
      fs.readdirSync(bundleDir).forEach(f => {
        const stat = fs.statSync(path.join(bundleDir, f));
        files.push({ name: f, path: `bundle/release/${f}`, size: stat.size, type: 'AAB' });
      });
    }
    if (fs.existsSync(apkDir)) {
      fs.readdirSync(apkDir).forEach(f => {
        if (f.endsWith('.apk')) {
          const stat = fs.statSync(path.join(apkDir, f));
          files.push({ name: f, path: `flutter-apk/${f}`, size: stat.size, type: 'APK' });
        }
      });
    }
    
    const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>TANHO Build Files</title>
  <style>
    body { font-family: system-ui; max-width: 600px; margin: 2rem auto; padding: 1rem; background: #111; color: #fff; }
    h1 { color: #5B41D9; }
    .file { display: flex; justify-content: space-between; align-items: center; padding: 1rem; background: #1a1c23; border-radius: 12px; margin: 0.5rem 0; border: 1px solid #333; }
    .file-info { display: flex; flex-direction: column; gap: 0.25rem; }
    .file-name { font-weight: 600; }
    .file-meta { font-size: 0.85rem; color: #888; }
    .btn { background: linear-gradient(135deg, #5B41D9, #8C7AE6); color: white; padding: 0.75rem 1.5rem; border-radius: 8px; text-decoration: none; font-weight: 600; display: inline-block; }
    .btn:hover { opacity: 0.9; }
    .badge { background: #5B41D9; padding: 0.2rem 0.5rem; border-radius: 4px; font-size: 0.75rem; margin-left: 0.5rem; }
  </style>
</head>
<body>
  <h1>📦 TANHO Build Files v1.3.5+35</h1>
  <p>Click to download. Files are signed release builds.</p>
  ${files.map(f => `
    <div class="file">
      <div class="file-info">
        <span class="file-name">${f.name}<span class="badge">${f.type}</span></span>
        <span class="file-meta">${(f.size/1024/1024).toFixed(1)} MB</span>
      </div>
      <a class="btn" href="/download/${f.path}">Download</a>
    </div>
  `).join('')}
  <p style="color:#888;font-size:0.85rem;margin-top:2rem;">Served from ${FILE_DIR}</p>
</body>
</html>`;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end(html);
  } else if (url.pathname.startsWith('/download/')) {
    const filePath = path.join(FILE_DIR, url.pathname.slice(10));
    if (!fs.existsSync(filePath)) {
      res.statusCode = 404;
      return res.end('Not found');
    }
    const stat = fs.statSync(filePath);
    res.setHeader('Content-Length', stat.size);
    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('Content-Disposition', `attachment; filename="${path.basename(filePath)}"`);
    fs.createReadStream(filePath).pipe(res);
  } else {
    res.statusCode = 404;
    res.end('Not found');
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`File server running on http://0.0.0.0:${PORT}`);
});
