#!/bin/bash
# MAXMZH 关键数据备份：后台数据（公告/账号）+ nginx 站点配置 + 服务定义
# 由 maxmzh-backup.timer 每日触发，保留最近 14 份
set -e
DEST=/opt/maxmzh-admin/backups
mkdir -p "$DEST"
TS=$(date +%Y%m%d-%H%M%S)
tar -czf "$DEST/backup-$TS.tar.gz" -C / \
  opt/maxmzh-admin/data \
  etc/nginx/sites-available/maxmzh \
  etc/systemd/system/maxmzh-admin.service
ls -1t "$DEST"/backup-*.tar.gz | tail -n +15 | xargs -r rm -f
echo "backup done: backup-$TS.tar.gz ($(du -h "$DEST/backup-$TS.tar.gz" | cut -f1))"
