#!/bin/bash
# 在 VPS 上搭建社区自托管地基：PostgreSQL + mmc-api 基础服务（与 Supabase 并行，不接线上流量）
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== 1. 安装 PostgreSQL =="
if ! command -v psql >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql >/dev/null
fi
psql --version

echo "== 2. 内存调优（1GB 小机） =="
PGCONF=$(ls -d /etc/postgresql/*/main)
sudo mkdir -p "$PGCONF/conf.d"
printf "shared_buffers = 128MB\nwork_mem = 4MB\nmax_connections = 50\neffective_cache_size = 256MB\n" | sudo tee "$PGCONF/conf.d/mmc.conf" >/dev/null
sudo systemctl enable --now postgresql
sudo systemctl restart postgresql
pg_isready -h 127.0.0.1 -p 5432

echo "== 3. 建库与账号（密码只存 VPS 本地，不外传） =="
sudo mkdir -p /opt/mmc-api
if [ ! -f /opt/mmc-api/db.env ]; then
    PW=$(openssl rand -hex 24)
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE USER mmc WITH PASSWORD '$PW';"
    sudo -u postgres createdb -O mmc mmc
    printf "DATABASE_URL=postgres://mmc:%s@127.0.0.1:5432/mmc\n" "$PW" | sudo tee /opt/mmc-api/db.env >/dev/null
    sudo chown ops:ops /opt/mmc-api/db.env
    sudo chmod 600 /opt/mmc-api/db.env
    echo "db created"
else
    echo "db.env 已存在，跳过建库"
fi

echo "== 4. 安装 mmc-api 服务 =="
sudo cp "$SRC_DIR/server.py" /opt/mmc-api/server.py
sudo cp "$SRC_DIR/mmc-api.service" /etc/systemd/system/
sudo chown -R ops:ops /opt/mmc-api
sudo systemctl daemon-reload
sudo systemctl enable --now mmc-api
sleep 1
systemctl is-active mmc-api
echo "== 5. 自检 =="
curl -s -m 5 http://127.0.0.1:8791/health; echo
curl -s -m 5 http://127.0.0.1:8791/; echo
sudo -u postgres psql -c "\l" | grep -w mmc || true
free -m | head -2
