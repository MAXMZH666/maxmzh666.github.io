#!/usr/bin/env python3
"""mmc-api：社区自托管基础服务（与 Supabase 并行运行的地基，暂不接线上流量）。
目前只提供健康检查；后续功能（存储/接口）在此扩展。"""
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("MMC_API_PORT", "8791"))


def db_up():
    try:
        r = subprocess.run(["/usr/bin/pg_isready", "-h", "127.0.0.1", "-p", "5432"],
                           capture_output=True, timeout=5)
        return r.returncode == 0
    except Exception:
        return False


class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True, "db": db_up()})
        elif self.path == "/":
            self._json(200, {"service": "mmc-api", "status": "foundation", "ws": WS_PORT})
        else:
            self._json(404, {"error": "not found"})



# ---------------- WebSocket 实时未读推送（8792，与 Supabase 并行） ----------------
import asyncio
import urllib.request

SUPABASE_URL = "https://xkvpzxxtcnocofnsezpy.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhrdnB6eHh0Y25vY29mbnNlenB5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5MTY4MzQsImV4cCI6MjEwNjQ5MjgzNH0.zTpvyEsutA9hV_UIg36g5owBRnxdHaI-sy_fLUsu6ec"
WS_PORT = int(os.environ.get("MMC_WS_PORT", "8792"))


def _sb_get(path, token):
    req = urllib.request.Request(
        SUPABASE_URL + path,
        headers={"apikey": SUPABASE_ANON_KEY, "Authorization": "Bearer " + token,
                 "Prefer": "count=exact", "Range": "0-0"})
    with urllib.request.urlopen(req, timeout=6) as r:
        return r.status, r.headers, r.read()


def _validate_token(token):
    try:
        status, _, body = _sb_get("/auth/v1/user", token)
        if status == 200:
            return json.loads(body)["id"]
    except Exception:
        return None
    return None


def _count(path, token):
    _, headers, _ = _sb_get("/rest/v1/" + path, token)
    total = headers.get("Content-Range", "").rsplit("/", 1)[-1]
    return int(total) if total.isdigit() else 0


def _poll_unread(uid, token):
    n = _count("notifications?user_id=eq.%s&is_read=eq.false&select=id" % uid, token)
    m = _count("direct_messages?receiver_id=eq.%s&read_at=is.null&select=id" % uid, token)
    return (n, m)


async def _ws_handler(ws, path=None):
    try:
        raw = await asyncio.wait_for(ws.recv(), timeout=10)
        token = json.loads(raw).get("token", "")
    except Exception:
        await ws.close(code=4001)
        return
    loop = asyncio.get_running_loop()
    uid = await loop.run_in_executor(None, _validate_token, token)
    if not uid:
        await ws.send(json.dumps({"type": "error", "error": "auth"}))
        await ws.close(code=4003)
        return
    await ws.send(json.dumps({"type": "ready"}))
    last = None
    try:
        while True:
            cur = await loop.run_in_executor(None, _poll_unread, uid, token)
            if cur != last:
                last = cur
                await ws.send(json.dumps({"type": "unread", "notifications": cur[0], "messages": cur[1]}))
            await asyncio.sleep(5)
    except Exception:
        return


async def _ws_main():
    import websockets
    async with websockets.serve(_ws_handler, "127.0.0.1", WS_PORT):
        print(f"mmc-api ws listening on 127.0.0.1:{WS_PORT}", flush=True)
        await asyncio.Future()

if __name__ == "__main__":
    import threading
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print(f"mmc-api listening on 127.0.0.1:{PORT}", flush=True)
    asyncio.run(_ws_main())
