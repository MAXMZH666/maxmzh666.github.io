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
            self._json(200, {"service": "mmc-api", "status": "foundation"})
        else:
            self._json(404, {"error": "not found"})


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    print(f"mmc-api listening on 127.0.0.1:{PORT}", flush=True)
    srv.serve_forever()
