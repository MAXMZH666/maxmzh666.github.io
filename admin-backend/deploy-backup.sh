#!/bin/bash
# 在 VPS 上安装每日备份（以 ops 运行，sudo 免密）
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
sudo cp "$SRC_DIR/backup.sh" /opt/maxmzh-admin/backup.sh
sudo chmod 755 /opt/maxmzh-admin/backup.sh
sudo cp "$SRC_DIR/maxmzh-backup.service" "$SRC_DIR/maxmzh-backup.timer" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now maxmzh-backup.timer
echo "== 立即跑一次备份 =="
sudo systemctl start maxmzh-backup.service
sudo systemctl status maxmzh-backup.service --no-pager | head -5 || true
echo "== 备份目录 =="
ls -la /opt/maxmzh-admin/backups/
echo "== 定时器 =="
systemctl list-timers maxmzh-backup.timer --no-pager | head -4
