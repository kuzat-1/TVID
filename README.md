# Stream Backend

Backend microservice for extracting direct stream URLs from VK Video and YouTube.

## Features

- **VK Video**: Extract HLS (.m3u8) or MP4 stream URLs from VK videos
- **YouTube**: Extract direct stream URLs using yt-dlp
- **CORS enabled** for web/mobile clients

## Requirements

- Node.js 18+
- yt-dlp installed system-wide (`pip install yt-dlp` or `brew install yt-dlp`)

## Installation

```bash
pnpm install
```

## Configuration

Create `.env` file:

```env
PORT=3000
NODE_ENV=development
VK_USER_AGENT=Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36
YT_DLP_PATH=yt-dlp
```

## Running

```bash
# Development
pnpm dev

# Production
pnpm start
```

## API Endpoints

### VK Video Stream

```
GET /api/vk/stream?oid={owner_id}&id={video_id}&hash={hash}
```

**Parameters:**
- `oid` (required): VK owner ID (can be negative for groups)
- `id` (required): VK video ID
- `hash` (optional): Video hash for private videos

**Response:**
```json
{
  "success": true,
  "provider": "vk",
  "hls_url": "https://...",
  "headers": {
    "Referer": "https://vk.com/",
    "User-Agent": "Mozilla/5.0..."
  }
}
```

### YouTube Stream

```
GET /api/yt/stream?v={video_id}
```

**Parameters:**
- `v` (required): YouTube video ID

**Response:**
```json
{
  "success": true,
  "provider": "youtube",
  "stream_url": "https://googlevideo.com/...",
  "headers": {
    "Referer": "https://www.youtube.com/",
    "User-Agent": "Mozilla/5.0..."
  }
}
```

### Health Check

```
GET /health
```

## Testing with curl

```bash
# VK Video
curl "http://localhost:3000/api/vk/stream?oid=-123456789&id=456239017"

# YouTube
curl "http://localhost:3000/api/yt/stream?v=dQw4w9WgXcQ"

# Health
curl http://localhost:3000/health
```

## Docker

```bash
docker-compose up -d
```

## Project Structure

```
stream-backend/
├── src/
│   ├── index.js          # Entry point
│   ├── routes/
│   │   ├── vk.js         # VK routes
│   │   └── youtube.js    # YouTube routes
│   └── services/
│       ├── vkService.js  # VK extraction logic
│       └── ytService.js  # YouTube extraction logic
├── .env                  # Environment variables
├── package.json
├── Dockerfile
├── docker-compose.yml
└── README.md
```