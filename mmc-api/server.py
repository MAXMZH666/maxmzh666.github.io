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
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "https://maxmzh.com")
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

    def _client_ip(self):
        return (self.headers.get("CF-Connecting-IP")
                or (self.headers.get("X-Forwarded-For") or "").split(",")[0].strip()
                or self.client_address[0])

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "https://maxmzh.com")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except Exception:
            n = 0
        raw = self.rfile.read(n) if n > 0 else b""
        ip = self._client_ip()
        try:
            if path == "/img/upload":
                code, obj = img_upload(self.headers, raw)
            elif path in ("/auth/send-code", "/auth/verify-register", "/stats/hit"):
                try:
                    body = json.loads(raw or b"{}")
                except Exception:
                    self._json(400, {"error": "bad json"})
                    return
                if path == "/auth/send-code":
                    code, obj = auth_send_code(body, ip)
                elif path == "/auth/verify-register":
                    code, obj = auth_verify_register(body)
                else:
                    code, obj = stats_hit(body, ip)
            else:
                code, obj = 404, {"error": "not found"}
        except Exception as e:
            code, obj = 500, {"error": str(e)}
        self._json(code, obj)



# ---------------- 邮箱验证码注册（/auth/*，从 Cloudflare Worker 移植到自托管） ----------------
import hashlib
import re
import secrets as _secrets
import threading
import urllib.error
from datetime import datetime, timezone, timedelta

SB_URL = "https://xkvpzxxtcnocofnsezpy.supabase.co"
_AUTH_ENV_PATH = os.environ.get("MMC_AUTH_ENV", "/opt/mmc-api/auth.env")


def _auth_env(name):
    v = os.environ.get(name)
    if v:
        return v
    try:
        with open(_AUTH_ENV_PATH) as f:
            for line in f:
                line = line.strip()
                if line.startswith(name + "="):
                    return line[len(name) + 1:].strip()
    except Exception:
        pass
    raise RuntimeError("missing env: " + name)


def _svc_headers(extra=None):
    key = _auth_env("SUPABASE_SERVICE_KEY")
    h = {"apikey": key, "Authorization": "Bearer " + key,
         "Content-Type": "application/json"}
    if extra:
        h.update(extra)
    return h


def _http(method, url, headers, body=None, timeout=15):
    req = urllib.request.Request(
        url, method=method, headers=headers,
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, (json.loads(raw) if raw else None)
        except Exception:
            return e.code, None
    except Exception:
        return 0, None


def _sha256hex(s):
    return hashlib.sha256(s.encode()).hexdigest()


def _parse_ts(s):
    return datetime.fromisoformat(str(s).replace("Z", "+00:00"))


_rate_lock = threading.Lock()
_rate_map = {}


def _check_code_rate(ip):
    now = datetime.now(timezone.utc).timestamp()
    with _rate_lock:
        rec = _rate_map.get(ip)
        if not rec or now - rec[0] > 3600:
            _rate_map[ip] = (now, 1)
            return True
        _rate_map[ip] = (rec[0], rec[1] + 1)
        return rec[1] + 1 <= 10


_EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$")


def auth_send_code(b, ip):
    email = str(b.get("email") or "").strip().lower()
    if not _EMAIL_RE.match(email) or len(email) > 254:
        return 400, {"error": "邮箱格式不正确"}
    if not _check_code_rate(ip):
        return 429, {"error": "发送太频繁，请稍后再试"}
    base = SB_URL
    st, rows = _http("GET", base + "/rest/v1/email_codes?email=eq."
                     + urllib.request.quote(email) + "&select=created_at",
                     _svc_headers())
    if st == 200 and rows and rows[0]:
        if (datetime.now(timezone.utc) - _parse_ts(rows[0]["created_at"])).total_seconds() < 60:
            return 429, {"error": "发送太频繁，请 60 秒后再试"}
    code = "%06d" % _secrets.randbelow(1000000)
    h = _sha256hex(email + ":" + code + ":" + _auth_env("EMAIL_CODE_SECRET"))
    now = datetime.now(timezone.utc)
    st, _ = _http("POST", base + "/rest/v1/email_codes",
                  _svc_headers({"Prefer": "resolution=merge-duplicates,return=minimal"}),
                  {"email": email, "code_hash": h, "attempts": 0,
                   "created_at": now.isoformat(),
                   "expires_at": (now + timedelta(seconds=600)).isoformat()})
    if not (200 <= st < 300):
        return 500, {"error": "验证码保存失败，请稍后再试"}
    st, _ = _http("POST", "https://api.resend.com/emails",
                  {"Authorization": "Bearer " + _auth_env("RESEND_API_KEY"),
                   "Content-Type": "application/json",
                   "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"},
                  {"from": "MAX社区 <noreply@maxmzh.com>", "to": [email],
                   "subject": "【MAX社区】注册验证码：" + code,
                   "text": "你的 MAX社区 注册验证码是：" + code + "\n\n10 分钟内有效，请勿告诉他人。\n如非本人操作，请忽略本邮件。",
                   "html": '<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px">'
                           '<h2 style="color:#4d7cfe;margin:0 0 12px">MAX社区 注册验证码</h2>'
                           '<p>你的验证码是：</p>'
                           '<p style="font-size:32px;font-weight:700;letter-spacing:8px;color:#111">' + code + '</p>'
                           '<p style="color:#666">10 分钟内有效，请勿告诉他人。如非本人操作，请忽略本邮件。</p></div>'})
    if not (200 <= st < 300):
        _http("DELETE", base + "/rest/v1/email_codes?email=eq."
              + urllib.request.quote(email), _svc_headers())
        return 502, {"error": "验证码发送失败，请稍后再试"}
    return 200, {"ok": True}


def auth_verify_register(b):
    email = str(b.get("email") or "").strip().lower()
    code = str(b.get("code") or "").strip()
    pw = str(b.get("password") or "")
    name = str(b.get("username") or "").strip()
    if not _EMAIL_RE.match(email):
        return 400, {"error": "邮箱格式不正确"}
    if not re.match(r"^\d{6}$", code):
        return 400, {"error": "请输入 6 位验证码"}
    if not (6 <= len(pw) <= 72):
        return 400, {"error": "密码至少 6 位"}
    if not name or len(name) > 20 or re.search(r"[<>&\"'\\]", name):
        return 400, {"error": "用户名不合法（1-20 字，不能含特殊符号）"}
    base = SB_URL
    q = urllib.request.quote(email)
    st, rows = _http("GET", base + "/rest/v1/email_codes?email=eq." + q
                     + "&select=code_hash,attempts,expires_at", _svc_headers())
    row = rows[0] if (st == 200 and rows) else None
    if not row:
        return 400, {"error": "验证码不存在或已过期，请重新获取"}

    def del_code():
        _http("DELETE", base + "/rest/v1/email_codes?email=eq." + q, _svc_headers())

    if _parse_ts(row["expires_at"]) < datetime.now(timezone.utc):
        del_code()
        return 400, {"error": "验证码已过期，请重新获取"}
    if row["attempts"] >= 5:
        del_code()
        return 400, {"error": "验证码错误次数过多，请重新获取"}
    h = _sha256hex(email + ":" + code + ":" + _auth_env("EMAIL_CODE_SECRET"))
    if h != row["code_hash"]:
        _http("PATCH", base + "/rest/v1/email_codes?email=eq." + q,
              _svc_headers(), {"attempts": row["attempts"] + 1})
        return 400, {"error": "验证码不正确"}
    st, prows = _http("GET", base + "/rest/v1/profiles?username=eq."
                      + urllib.request.quote(name) + "&select=id", _svc_headers())
    if st == 200 and prows:
        return 409, {"error": "用户名已被占用，换一个试试"}
    st, cu = _http("POST", base + "/auth/v1/admin/users", _svc_headers(),
                   {"email": email, "password": pw, "email_confirm": True,
                    "user_metadata": {"username": name}})
    if not (200 <= st < 300):
        msg = ""
        if isinstance(cu, dict):
            msg = str(cu.get("msg") or cu.get("message") or cu.get("error") or "")
        if re.search(r"already|exists|registered", msg, re.I):
            del_code()
            return 400, {"error": "该邮箱已注册，请直接登录"}
        return 500, {"error": "注册失败，请稍后再试"}
    del_code()
    return 200, {"ok": True}


# ---------------- 自建访问统计（/stats/hit，SQLite，替代不蒜子） ----------------
import sqlite3

_STATS_DB = os.environ.get("MMC_STATS_DB", "/opt/mmc-api/stats.db")
_stats_lock = threading.Lock()


def _stats_conn():
    conn = sqlite3.connect(_STATS_DB, timeout=5)
    conn.execute("CREATE TABLE IF NOT EXISTS pv (path TEXT, day TEXT, n INTEGER, PRIMARY KEY (path, day))")
    conn.execute("CREATE TABLE IF NOT EXISTS visitors (day TEXT, ip_hash TEXT, PRIMARY KEY (day, ip_hash))")
    return conn


def stats_hit(b, ip):
    path = str(b.get("path") or "")[:200]
    if not path.startswith("/"):
        return 400, {"error": "bad path"}
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    ip_hash = _sha256hex(day + "|" + ip)
    with _stats_lock:
        conn = _stats_conn()
        try:
            conn.execute("INSERT INTO pv (path, day, n) VALUES (?, ?, 1) "
                         "ON CONFLICT(path, day) DO UPDATE SET n = n + 1", (path, day))
            conn.execute("INSERT OR IGNORE INTO visitors (day, ip_hash) VALUES (?, ?)", (day, ip_hash))
            conn.commit()
            site_pv = conn.execute("SELECT COALESCE(SUM(n), 0) FROM pv").fetchone()[0]
            page_pv = conn.execute("SELECT COALESCE(SUM(n), 0) FROM pv WHERE path = ?", (path,)).fetchone()[0]
            site_uv = conn.execute("SELECT COUNT(*) FROM visitors").fetchone()[0]
        finally:
            conn.close()
    return 200, {"site_pv": site_pv, "page_pv": page_pv, "site_uv": site_uv}


# ---------------- 图床（/img/upload，MAX 账号登录后上传，文件存本机盘） ----------------
IMG_DIR = os.environ.get("MMC_IMG_DIR", "/opt/mmc-api/img")
_IMG_TYPES = {
    "png": (b"\x89PNG\r\n\x1a\n", "image/png"),
    "jpg": (b"\xff\xd8\xff", "image/jpeg"),
    "gif": (b"GIF8", "image/gif"),
    "webp": (b"RIFF", "image/webp"),
}


def _sniff_img(data):
    for ext, (magic, _mime) in _IMG_TYPES.items():
        if data.startswith(magic):
            if ext == "webp" and data[8:12] != b"WEBP":
                return None
            return ext
    return None


def img_upload(headers, raw):
    auth = headers.get("Authorization") or ""
    token = auth[7:] if auth.startswith("Bearer ") else ""
    if not token:
        return 401, {"error": "请先登录 MAX 账号"}
    uid = _validate_token(token)
    if not uid:
        return 401, {"error": "登录已过期，请重新登录"}
    if not raw or len(raw) > 5 * 1024 * 1024:
        return 400, {"error": "图片为空或超过 5MB"}
    ext = _sniff_img(raw)
    if not ext:
        return 400, {"error": "只支持 PNG / JPG / GIF / WebP 图片"}
    sub = datetime.now(timezone.utc).strftime("%Y%m")
    name = "%s-%s.%s" % (uid[:8], _secrets.token_hex(6), ext)
    dest_dir = os.path.join(IMG_DIR, sub)
    os.makedirs(dest_dir, exist_ok=True)
    with open(os.path.join(dest_dir, name), "wb") as f:
        f.write(raw)
    return 200, {"url": "https://img.maxmzh.com/i/%s/%s" % (sub, name)}


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
