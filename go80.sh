#!/bin/bash
# Переключение kuzat.ru на порт 80.
# Запускать от пользователя opencode ПОСЛЕ того, как рут освободил порт:
#   kill 275827   (или: pkill -f "http.server 80")
#   setcap 'cap_net_bind_service=+ep' /usr/bin/node
cd /home/opencode/projects/stream-backend || exit 1
pkill -f "projects/stream-backend/src/index" 2>/dev/null
sleep 1
BACKEND_PORT=80 setsid node src/index.js >> logs/out.log 2>> logs/err.log < /dev/null &
sleep 3
curl -s -m 8 http://127.0.0.1:80/health && echo "" && echo "OK: kuzat.ru работает на :80"
