#!/bin/bash
# 上线子域名服务：api.maxmzh.com（接口域名）+ img.maxmzh.com（图床）+ 主站 /stats/ 自建统计
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1) mmc-api 新代码（/img/upload、/stats/hit）
sudo cp "$SRC_DIR/server.py" /opt/mmc-api/server.py
sudo systemctl restart mmc-api
sleep 2
systemctl is-active mmc-api
curl -s -m 5 http://127.0.0.1:8791/health; echo

# 2) 图床首页
sudo mkdir -p /opt/mmc-api/img
sudo cp "$SRC_DIR/img-index.html" /opt/mmc-api/img/index.html

# 3) 主站加 /stats/ 反代（幂等，失败回滚）
SITE=/etc/nginx/sites-available/maxmzh
sudo cp "$SITE" "$SITE.bak-$(date +%Y%m%d%H%M%S)"
sudo python3 "$SRC_DIR/nginx_insert.py" "$SITE" "$SRC_DIR/nginx-stats.conf" "/stats/"

# 4) 子域名虚拟主机（证书沿用现有 Let's Encrypt 证书）
CERT_DIR=$(ls -d /etc/letsencrypt/live/*/ | head -1)
echo "cert dir: $CERT_DIR"
for v in api img; do
    sed -e "s|@CERT@|${CERT_DIR}fullchain.pem|" -e "s|@KEY@|${CERT_DIR}privkey.pem|" \
        "$SRC_DIR/vhost-$v.conf" | sudo tee /etc/nginx/sites-available/$v.maxmzh.com >/dev/null
    sudo ln -sf /etc/nginx/sites-available/$v.maxmzh.com /etc/nginx/sites-enabled/$v.maxmzh.com
done

if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "nginx reloaded"
else
    echo "nginx 配置校验失败，回滚！"
    sudo rm -f /etc/nginx/sites-enabled/api.maxmzh.com /etc/nginx/sites-enabled/img.maxmzh.com
    sudo cp "$(ls -t $SITE.bak-* | head -1)" "$SITE"
    sudo nginx -t && sudo systemctl reload nginx
    exit 1
fi

# 5) 自检（本机直连 + 公网）
sleep 1
echo "api health (public): $(curl -s -m 8 https://api.maxmzh.com/health || echo FAIL)"
echo "img home (public): $(curl -s -o /dev/null -w '%{http_code}' -m 8 https://img.maxmzh.com/ || echo FAIL)"
echo "stats hit (public): $(curl -s -m 8 -X POST https://maxmzh.com/stats/hit -H 'Content-Type: application/json' -d '{"path":"/deploy-check"}' || echo FAIL)"
