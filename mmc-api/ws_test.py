#!/usr/bin/env python3
"""WS 网关自检：无效令牌应被拒绝（{"type":"error"} 后断开）。"""
import json
from websockets.sync.client import connect

with connect("ws://127.0.0.1:8792", open_timeout=5) as ws:
    ws.send(json.dumps({"token": "invalid-token-for-test"}))
    msg = ws.recv(timeout=5)
    data = json.loads(msg)
    assert data.get("type") == "error", f"unexpected reply: {data}"
print("WS_TEST_OK: invalid token rejected")
