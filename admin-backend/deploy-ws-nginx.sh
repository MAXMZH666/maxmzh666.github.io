#!/bin/bash
# 给 nginx 两个 server 块都加上 /ws/ 反代（WebSocket 网关），校验失败自动回滚
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SITE=/etc/nginx/sites-available/maxmzh
sudo cp "$SITE" "$SITE.bak-$(date +%Y%m%d%H%M%S)"
sudo python3 "$SRC_DIR/nginx_insert.py" "$SITE" "$SRC_DIR/nginx-ws.conf" "8792"
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "nginx reloaded"
else
    echo "nginx 配置校验失败，回滚！"
    sudo cp "$(ls -t $SITE.bak-* | head -1)" "$SITE"
    sudo nginx -t && sudo systemctl reload nginx
    exit 1
fi
sleep 1
CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -H 'Upgrade: websocket' -H 'Connection: Upgrade' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Version: 13' https://maxmzh.com/ws/)
echo "ws handshake http_code: $CODE"
