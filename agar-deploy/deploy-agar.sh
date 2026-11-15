#!/bin/bash
# 部署 MAX Agar 游戏服务：Node 运行时 + systemd 服务 agar + nginx /agar/ 与 /socket.io/ 反代。
# 幂等：可重复运行（更新代码/配置）。nginx 改动失败自动回滚。
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
# scp -r 到已存在目录会多套一层，自动下钻
if [ ! -f "$SRC_DIR/nginx-agar.conf" ] && [ -f "$SRC_DIR/agar-deploy/nginx-agar.conf" ]; then
    SRC_DIR="$SRC_DIR/agar-deploy"
fi
TARBALL="$HOME/agar-deploy.tar.gz"
[ -f "$TARBALL" ] || { echo "missing $TARBALL"; exit 1; }

# 1) Node 运行时（缺失时装官方静态包到 /opt/node20）
NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
    if [ ! -x /opt/node20/bin/node ]; then
        cd /tmp
        curl -fsSL -o node20.tar.xz https://nodejs.org/dist/v20.18.1/node-v20.18.1-linux-x64.tar.xz
        sudo mkdir -p /opt/node20
        sudo tar -xJf node20.tar.xz -C /opt/node20 --strip-components=1
        rm -f node20.tar.xz
    fi
    NODE_BIN=/opt/node20/bin/node
fi
echo "node: $NODE_BIN ($($NODE_BIN --version))"

# 2) 游戏文件到 /opt/agar（保留已有 db 数据目录）
sudo mkdir -p /opt/agar
sudo tar -xzf "$TARBALL" -C /opt/agar
sudo chown -R ops:ops /opt/agar
# 只监听本机，公网统一走 nginx
sed -i 's/host: "0.0.0.0"/host: "127.0.0.1"/' /opt/agar/config.js

# 3) systemd 服务
sudo tee /etc/systemd/system/agar.service >/dev/null <<UNIT
[Unit]
Description=MAX Agar game server
After=network.target

[Service]
Type=simple
User=ops
WorkingDirectory=/opt/agar
ExecStart=$NODE_BIN /opt/agar/src/server/server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable agar >/dev/null 2>&1 || true
sudo systemctl restart agar
sleep 3
systemctl is-active agar
curl -s -m 5 -o /dev/null -w "local game page: %{http_code}\n" http://127.0.0.1:3000/

# 4) nginx 反代（备份 + 插入 + 校验，失败回滚）
SITE=/etc/nginx/sites-available/maxmzh
sudo cp "$SITE" "$SITE.bak-$(date +%Y%m%d%H%M%S)"
sudo python3 "$SRC_DIR/nginx_insert.py" "$SITE" "$SRC_DIR/nginx-agar.conf" "/agar/"
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "nginx reloaded"
else
    echo "nginx 配置校验失败，回滚！"
    sudo cp "$(ls -t $SITE.bak-* | head -1)" "$SITE"
    sudo nginx -t && sudo systemctl reload nginx
    exit 1
fi

# 5) 公网自检
sleep 1
curl -s -m 8 -o /dev/null -w "public /agar/: %{http_code}\n" https://maxmzh.com/agar/
echo "public socket.io handshake:"
curl -s -m 8 "https://maxmzh.com/socket.io/?EIO=4&transport=polling" | head -c 80; echo
echo "deploy-agar done"
