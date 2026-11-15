#!/bin/bash
# 给 MAX Agar 开直连子域名 agar.maxmzh.com（DNS-only 绕 Cloudflare 代理，降低联机延迟）：
# 找 certbot 的 Cloudflare 凭据 -> 建 DNS A 记录 -> 确认证书覆盖 -> 写 nginx 独立站点 -> 自检。
# 幂等可重跑；nginx 校验失败自动回滚。凭据只在脚本内使用，绝不打印。
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$SRC_DIR/setup-agar-domain.sh" ] && [ -f "$SRC_DIR/agar-deploy/setup-agar-domain.sh" ]; then
    SRC_DIR="$SRC_DIR/agar-deploy"
fi
DOMAIN="agar.maxmzh.com"
VPS_IP="129.225.130.130"

echo "=== 服务器负载速览 ==="
uptime || true
ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -8 || true

echo "=== 查找 Cloudflare 凭据（certbot） ==="
INI=""
for c in /root/.secrets/certbot/cloudflare.ini /etc/letsencrypt/cloudflare.ini \
         /home/ops/.secrets/certbot/cloudflare.ini /root/.cloudflare.ini; do
    if sudo test -f "$c"; then INI="$c"; break; fi
done
if [ -z "$INI" ]; then
    FOUND="$(sudo find /root /etc/letsencrypt /home/ops -name '*cloudflare*.ini' 2>/dev/null | head -1 || true)"
    [ -n "$FOUND" ] && INI="$FOUND"
fi
[ -n "$INI" ] || { echo "NO_CF_CREDS: 服务器上没找到 certbot 的 Cloudflare 凭据文件"; exit 2; }
echo "creds file: $INI"
TOKEN="$(sudo grep -E 'dns_cloudflare_api_token|api_token' "$INI" | head -1 | cut -d= -f2- | tr -d ' "')"
[ -n "$TOKEN" ] || { echo "NO_CF_TOKEN: 凭据文件里没有 api token"; exit 2; }
export CF_TOKEN="$TOKEN"

echo "=== 创建/更新 DNS 记录（DNS-only 直连） ==="
python3 - <<'PYEOF'
import json, os, urllib.request

token = os.environ["CF_TOKEN"]
def api(method, path, data=None):
    req = urllib.request.Request("https://api.cloudflare.com/client/v4" + path,
        method=method, data=json.dumps(data).encode() if data else None,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)

zones = api("GET", "/zones?name=maxmzh.com")
zid = zones["result"][0]["id"]
print("zone ok")
recs = api("GET", f"/zones/{zid}/dns_records?name=agar.maxmzh.com")
body = {"type": "A", "name": "agar", "content": "129.225.130.130", "proxied": False, "ttl": 120}
if recs["result"]:
    rid = recs["result"][0]["id"]
    api("PUT", f"/zones/{zid}/dns_records/{rid}", body)
    print("dns record updated")
else:
    api("POST", f"/zones/{zid}/dns_records", body)
    print("dns record created")
PYEOF

echo "=== 确认证书覆盖 ==="
CERT_PATH="$(sudo grep -hoE 'ssl_certificate [^;]+' /etc/nginx/sites-available/maxmzh | head -1 | awk '{print $2}')"
echo "site cert: $CERT_PATH"
COVERED=0
if [ -n "$CERT_PATH" ] && sudo test -f "$CERT_PATH"; then
    SANS="$(sudo openssl x509 -in "$CERT_PATH" -noout -text 2>/dev/null | grep -A1 'Subject Alternative Name' | tail -1 || true)"
    echo "cert SANs: $SANS"
    case "$SANS" in *DNS:\*.maxmzh.com*|*DNS:agar.maxmzh.com*) COVERED=1;; esac
fi
if [ "$COVERED" = "1" ]; then
    KEY_PATH="$(sudo grep -hoE 'ssl_certificate_key [^;]+' /etc/nginx/sites-available/maxmzh | head -1 | awk '{print $2}')"
    echo "reuse wildcard cert"
else
    echo "issuing cert for $DOMAIN via certbot dns-cloudflare"
    if ! certbot plugins 2>/dev/null | grep -q dns-cloudflare; then
        sudo apt-get update -qq && sudo apt-get install -y -qq python3-certbot-dns-cloudflare
    fi
    sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials "$INI" \
        -d "$DOMAIN" --non-interactive --agree-tos
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
fi
echo "cert: $CERT_PATH"

echo "=== 写 nginx 独立站点 ==="
sudo tee /etc/nginx/sites-available/agar >/dev/null <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
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
    echo "nginx reloaded"
else
    echo "nginx 配置校验失败，回滚！"
    sudo rm -f /etc/nginx/sites-enabled/agar /etc/nginx/sites-available/agar
    sudo nginx -t && sudo systemctl reload nginx
    exit 1
fi

echo "=== 公网自检（等 DNS 生效，最多 60 秒） ==="
for i in $(seq 1 12); do
    sleep 5
    CODE="$(curl -s -m 8 -o /dev/null -w '%{http_code}' https://$DOMAIN/ || true)"
    echo "try $i: https://$DOMAIN/ -> $CODE"
    [ "$CODE" = "200" ] && break
done
curl -s -m 8 "https://$DOMAIN/socket.io/?EIO=4&transport=polling" | head -c 80; echo
echo "setup-agar-domain done"
