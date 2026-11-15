#!/bin/bash
# MAX Agar 直连子域名 v2：DNS 记录已在 Cloudflare 面板建好（DNS-only），本脚本在 VPS 上：
# 等 DNS 生效 -> 写 agar 的 nginx 站点（先 80）-> certbot --nginx 签证书并加 443 -> 自检。
# 幂等可重跑；nginx 校验失败自动回滚站点文件（证书已签发不受影响）。
set -e
DOMAIN="agar.maxmzh.com"
VPS_IP="129.225.130.130"

echo "=== 服务器负载速览 ==="
uptime || true
ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -8 || true

echo "=== 等待 DNS 生效（$DOMAIN -> $VPS_IP） ==="
OK=0
for i in $(seq 1 18); do
    RESOLVED="$(getent hosts $DOMAIN | awk '{print $1}' | head -1 || true)"
    echo "try $i: $RESOLVED"
    [ "$RESOLVED" = "$VPS_IP" ] && { OK=1; break; }
    sleep 5
done
[ "$OK" = "1" ] || { echo "DNS_NOT_READY: $DOMAIN 尚未解析到 $VPS_IP"; exit 3; }

echo "=== 写 nginx 站点（80 先行，certbot 随后加 443） ==="
sudo tee /etc/nginx/sites-available/agar >/dev/null <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX
sudo ln -sf /etc/nginx/sites-available/agar /etc/nginx/sites-enabled/agar
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "nginx reloaded (http)"
else
    echo "nginx 配置校验失败，回滚！"
    sudo rm -f /etc/nginx/sites-enabled/agar /etc/nginx/sites-available/agar
    sudo nginx -t && sudo systemctl reload nginx
    exit 1
fi

echo "=== 签发证书（certbot --nginx） ==="
if ! certbot plugins 2>/dev/null | grep -q '\-\-nginx'; then
    echo "installing certbot nginx plugin"
    sudo apt-get update -qq && sudo apt-get install -y -qq python3-certbot-nginx
fi
sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect || {
    echo "CERTBOT_FAILED: 证书签发失败（HTTP 站点已在运行，可重试）"
    exit 4
}
sudo nginx -t && sudo systemctl reload nginx

echo "=== 公网自检 ==="
sleep 2
curl -s -m 8 -o /dev/null -w "https://$DOMAIN/ -> %{http_code}\n" https://$DOMAIN/
curl -s -m 8 "https://$DOMAIN/socket.io/?EIO=4&transport=polling" | head -c 80; echo
echo "setup-agar-domain v2 done"
