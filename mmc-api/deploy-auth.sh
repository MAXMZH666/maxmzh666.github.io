#!/bin/bash
# 部署邮箱验证码接口：装 auth.env 与新版 server.py、给 nginx 加 /auth/ 反代（双块，失败回滚）、重启自检
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1) 机密 env（由 GitHub Actions 以 auth.env.in 文件形式送达，不入仓库）
if [ -f "$SRC_DIR/auth.env.in" ]; then
    sudo install -m 600 -o ops -g ops "$SRC_DIR/auth.env.in" /opt/mmc-api/auth.env
    rm -f "$SRC_DIR/auth.env.in"
    echo "auth.env installed"
else
    echo "WARN: auth.env.in 不存在，沿用现有 /opt/mmc-api/auth.env"
fi

# 2) 服务代码与重启
sudo cp "$SRC_DIR/server.py" /opt/mmc-api/server.py
sudo systemctl restart mmc-api
sleep 2
systemctl is-active mmc-api
curl -s -m 5 http://127.0.0.1:8791/health; echo

# 3) nginx /auth/ 反代（幂等插入，校验失败自动回滚）
SITE=/etc/nginx/sites-available/maxmzh
sudo cp "$SITE" "$SITE.bak-$(date +%Y%m%d%H%M%S)"
sudo python3 "$SRC_DIR/nginx_insert.py" "$SITE" "$SRC_DIR/nginx-auth.conf" "8791"
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "nginx reloaded"
else
    echo "nginx 配置校验失败，回滚！"
    sudo cp "$(ls -t $SITE.bak-* | head -1)" "$SITE"
    sudo nginx -t && sudo systemctl reload nginx
    exit 1
fi

# 4) 经公网自检：坏邮箱应被接口以 400 拒绝（证明路由+服务都通）
sleep 1
echo "send-code bad-email check:"
curl -s -m 8 -X POST https://maxmzh.com/auth/send-code -H 'Content-Type: application/json' -d '{"email":"bad"}'; echo

# 5) 子域名服务（api/img/自建统计）随本脚本一并部署
bash "$SRC_DIR/deploy-subdomains.sh"
