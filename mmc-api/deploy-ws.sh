#!/bin/bash
# 给 mmc-api 加上 WebSocket 实时推送（8792）：装 websockets 库、更新服务、自检
set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! python3 -c "import websockets" 2>/dev/null; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-websockets >/dev/null
fi
python3 -c "import websockets; print('websockets lib ok')"
sudo cp "$SRC_DIR/server.py" /opt/mmc-api/server.py
sudo systemctl restart mmc-api
sleep 2
systemctl is-active mmc-api
curl -s -m 5 http://127.0.0.1:8791/health; echo
python3 "$SRC_DIR/ws_test.py"
