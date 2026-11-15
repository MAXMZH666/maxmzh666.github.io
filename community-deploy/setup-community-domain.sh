#!/bin/bash
# MAX编程社区子域名（community.maxmzh.com）一次性配置脚本，在 VPS 上运行。
#   bash setup-community-domain.sh vhost     -> 等 DNS 生效后写子域名站点并自检
#   bash setup-community-domain.sh redirect  -> 给主站 443 块加社区页 301 跳转并自检
# 幂等可重跑；nginx 校验失败自动回滚。
set -e
PHASE="${1:-vhost}"
DOMAIN="community.maxmzh.com"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SITE_MAIN="/etc/nginx/sites-available/maxmzh"
SITE_COMM="/etc/nginx/sites-available/community"

echo "=== 服务器负载速览 ==="
uptime || true
free -m | head -2 || true

if [ "$PHASE" = "vhost" ]; then
    echo "=== 等待 DNS 生效（$DOMAIN） ==="
    OK=0
    for i in $(seq 1 24); do
        RESOLVED="$(getent hosts $DOMAIN | awk '{print $1}' | head -1 || true)"
        echo "try $i: ${RESOLVED:-none}"
        [ -n "$RESOLVED" ] && { OK=1; break; }
        sleep 5
    done
    [ "$OK" = "1" ] || { echo "DNS_NOT_READY: $DOMAIN 尚无解析记录"; exit 3; }

    CERT="/etc/letsencrypt/live/maxmzh.com/fullchain.pem"
    KEY="/etc/letsencrypt/live/maxmzh.com/privkey.pem"
    [ -f "$CERT" ] && [ -f "$KEY" ] || { echo "CERT_MISSING: $CERT / $KEY 不存在"; exit 4; }

    echo "=== 写子域名站点 ==="
    sed -e "s|@CERT@|$CERT|g" -e "s|@KEY@|$KEY|g" "$SRC_DIR/vhost-community.conf" | sudo tee "$SITE_COMM" >/dev/null
    sudo ln -sf "$SITE_COMM" /etc/nginx/sites-enabled/community
    if sudo nginx -t; then
        sudo systemctl reload nginx
        echo "nginx reloaded (community vhost)"
    else
        echo "nginx 配置校验失败，回滚！"
        sudo rm -f /etc/nginx/sites-enabled/community "$SITE_COMM"
        sudo nginx -t && sudo systemctl reload nginx
        exit 1
    fi

    echo "=== 自检（本机 Host 头） ==="
    sleep 1
    H1=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $DOMAIN" http://127.0.0.1/community-home.html || true)
    echo "http community-home: $H1"
    H2=$(curl -sk -o /dev/null -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/community-home.html" || true)
    echo "https community-home: $H2"
    H3=$(curl -sk -o /dev/null -w '%{http_code} %{redirect_url}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/" || true)
    echo "https root: $H3"
    [ "$H1" = "200" ] && [ "$H2" = "200" ] || { echo "SELF_CHECK_FAILED"; exit 5; }
    echo "VHOST_OK"

elif [ "$PHASE" = "redirect" ]; then
    echo "=== 给主站加社区页 301 跳转 ==="
    sudo cp "$SITE_MAIN" "$SITE_MAIN.bak-community-redirect"
    OUT=$(python3 "$SRC_DIR/nginx_redirect_insert.py" "$SITE_MAIN" | sudo tee /dev/stderr | tail -1 || true)
    if [ "$OUT" = "NO_TARGET_BLOCK" ]; then
        echo "未找到主站 443 块，已放弃（备份保留）"
        exit 6
    fi
    if sudo nginx -t; then
        sudo systemctl reload nginx
        echo "nginx reloaded (redirect)"
    else
        echo "nginx 配置校验失败，回滚！"
        sudo cp "$SITE_MAIN.bak-community-redirect" "$SITE_MAIN"
        sudo nginx -t && sudo systemctl reload nginx
        exit 1
    fi
    echo "=== 自检（本机 Host 头） ==="
    sleep 1
    R1=$(curl -sk -o /dev/null -w '%{http_code} %{redirect_url}' --resolve "maxmzh.com:443:127.0.0.1" "https://maxmzh.com/community-home.html" || true)
    echo "old community page: $R1"
    R2=$(curl -sk -o /dev/null -w '%{http_code}' --resolve "maxmzh.com:443:127.0.0.1" "https://maxmzh.com/index.html" || true)
    echo "main index (should stay 200): $R2"
    case "$R1" in
        "301 https://community.maxmzh.com/community-home.html") ;;
        *) echo "REDIRECT_CHECK_FAILED"; exit 7 ;;
    esac
    [ "$R2" = "200" ] || { echo "MAIN_SITE_CHECK_FAILED"; exit 8; }
    echo "REDIRECT_OK"
else
    echo "unknown phase: $PHASE (vhost|redirect)"
    exit 2
fi
