#!/usr/bin/env python3
"""WS 网关自检：无效令牌应被拒绝（{"type":"error"} 后断开）。用 asyncio 客户端 API，兼容旧版 websockets 库。"""
import asyncio
import json

import websockets


async def main():
    async with websockets.connect("ws://127.0.0.1:8792") as ws:
        await ws.send(json.dumps({"token": "invalid-token-for-test"}))
        msg = await asyncio.wait_for(ws.recv(), timeout=5)
        data = json.loads(msg)
        assert data.get("type") == "error", f"unexpected reply: {data}"
    print("WS_TEST_OK: invalid token rejected")


asyncio.get_event_loop().run_until_complete(main())
