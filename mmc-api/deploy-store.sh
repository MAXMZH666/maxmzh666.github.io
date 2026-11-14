#!/bin/bash
# 部署应用商店后台：装新版 server.py（/store/* 接口，SQLite 存 /opt/mmc-api/store.db）、
# 给 nginx 加 /store-api/ 反代（幂等插入，失败回滚）、重启自检。
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1) 服务代码与重启
sudo cp "$SRC_DIR/server.py" /opt/mmc-api/server.py
sudo systemctl restart mmc-api
sleep 2
systemctl is-active mmc-api
curl -s -m 5 http://127.0.0.1:8791/health; echo
curl -s -m 5 http://127.0.0.1:8791/store/announcement; echo

# 2) nginx /store-api/ 反代
SITE=/etc/nginx/sites-available/maxmzh
sudo cp "$SITE" "$SITE.bak-$(date +%Y%m%d%H%M%S)"
sudo python3 "$SRC_DIR/nginx_insert.py" "$SITE" "$SRC_DIR/nginx-store.conf" "/store-api/"
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "nginx reloaded"
else
    echo "nginx 配置校验失败，回滚！"
    sudo cp "$(ls -t $SITE.bak-* | head -1)" "$SITE"
    sudo nginx -t && sudo systemctl reload nginx
    exit 1
fi

# 3) 经公网自检：公告接口应返回 JSON；未登录发评论应 401
sleep 1
echo "public announcement check:"
curl -s -m 8 https://maxmzh.com/store-api/announcement; echo
echo "public comment noauth check (expect 401):"
curl -s -m 8 -o /dev/null -w "%{http_code}\n" -X POST https://maxmzh.com/store-api/comment \
  -H 'Content-Type: application/json' -d '{"app":"联机五子棋","content":"deploy check"}'
echo "deploy-store done"
