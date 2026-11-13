#!/bin/bash
# 在大阪 VPS 上部署 MAXMZH 网站后台（以 ops 身份运行，sudo 已免密）
# 用法：把本目录传到 VPS 后执行 bash deploy.sh
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR=/opt/maxmzh-admin

echo "== 1. 安装服务文件 =="
sudo mkdir -p "$APP_DIR/data"
sudo cp "$SRC_DIR/server.py" "$SRC_DIR/admin.html" "$APP_DIR/"
sudo chown -R ops:ops "$APP_DIR"

echo "== 2. 生成一次性设置码（若尚未设置密码）=="
if [ ! -f "$APP_DIR/data/auth.json" ]; then
    TOKEN=$(openssl rand -hex 10)
    echo "$TOKEN" > "$APP_DIR/data/setup-token.txt"
    chmod 600 "$APP_DIR/data/setup-token.txt"
    echo ">>> 设置码 SETUP TOKEN: $TOKEN"
else
    echo "已设置过密码，跳过"
fi

echo "== 3. systemd 服务 =="
sudo cp "$SRC_DIR/maxmzh-admin.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now maxmzh-admin
sleep 1
systemctl is-active maxmzh-admin

echo "== 4. nginx 日志格式（记录 Cloudflare 真实访客 IP）=="
if [ ! -f /etc/nginx/conf.d/cf-log.conf ]; then
    echo 'log_format cf_combined '"'"'$http_cf_connecting_ip $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"'"'"';' | sudo tee /etc/nginx/conf.d/cf-log.conf >/dev/null
fi

echo "== 5. nginx 站点接入 /api/ 与 /admin/ =="
SITE=/etc/nginx/sites-available/maxmzh
sudo cp "$SITE" "$SITE.bak-$(date +%Y%m%d%H%M%S)"
if ! grep -q "8790" "$SITE"; then
    # 在 server 块最后一个 } 前插入 location 片段，并把 access_log 切到 cf_combined
    python3 - "$SITE" "$SRC_DIR/nginx-admin-locations.conf" <<'PYEOF'
import sys
site_path, snippet_path = sys.argv[1], sys.argv[2]
src = open(site_path).read()
snippet = open(snippet_path).read()
lines = src.rstrip().rsplit("}", 1)
new = lines[0] + snippet + "}\n"
if "access_log" not in new:
    new = new.replace("server_name", "access_log /var/log/nginx/access.log cf_combined;\n    server_name", 1)
elif "cf_combined" not in new:
    import re
    new = re.sub(r"access_log\s+[^;]+;", "access_log /var/log/nginx/access.log cf_combined;", new, count=1)
open(site_path, "w").write(new)
print("site config updated")
PYEOF
fi
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "nginx 已重载"
else
    echo "nginx 配置校验失败，回滚！"
    sudo cp "$(ls -t $SITE.bak-* | head -1)" "$SITE"
    sudo nginx -t && sudo systemctl reload nginx
    exit 1
fi

echo "== 5b. 禁止通过 Web 访问仓库里的后台源码目录 =="
if ! grep -q "location ^~ /admin-backend/" "$SITE"; then
    sudo python3 - "$SITE" <<'PYEOF'
import sys
p = sys.argv[1]
src = open(p).read()
lines = src.rstrip().rsplit("}", 1)
open(p, "w").write(lines[0] + "\n    location ^~ /admin-backend/ { return 404; }\n}\n")
print("admin-backend deny added")
PYEOF
    if sudo nginx -t; then
        sudo systemctl reload nginx
    else
        echo "nginx 配置校验失败，回滚！"
        sudo cp "$(ls -t $SITE.bak-* | head -1)" "$SITE"
        sudo nginx -t && sudo systemctl reload nginx
        exit 1
    fi
fi

echo "== 6. 本机自检 =="
curl -s http://127.0.0.1:8790/api/news | head -c 200; echo
echo "部署完成。打开 https://maxmzh.com/admin/ 用设置码完成首次设置。"
