FROM node:20-alpine

RUN apk add --no-cache python3 py3-pip ffmpeg && \
    pip install --no-cache-dir --break-system-packages yt-dlp

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

RUN mkdir -p logs

EXPOSE 3000

CMD ["node", "index.js"]