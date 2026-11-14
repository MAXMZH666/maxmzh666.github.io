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

    _CORS_ORIGINS = ("https://maxmzh.com", "https://store.maxmzh.com")

    def _cors_origin(self):
        o = self.headers.get("Origin") or ""
        return o if o in self._CORS_ORIGINS else "https://maxmzh.com"

    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", self._cors_origin())
        self.send_header("Vary", "Origin")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/health":
            self._json(200, {"ok": True, "db": db_up()})
        elif path == "/":
            self._json(200, {"service": "mmc-api", "status": "foundation", "ws": WS_PORT})
        elif path == "/store/submission/file":
            code, data, fname = store_submission_file(self.headers, self.path)
            if data is None:
                self._json(code, {"error": fname})
            else:
                self.send_response(200)
                self.send_header("Content-Type", "application/vnd.android.package-archive")
                self.send_header("Content-Disposition", "attachment; filename*=UTF-8''" + fname)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                try:
                    self.wfile.write(data)
                except Exception:
                    pass
        elif path.startswith("/store/"):
            try:
                code, obj = store_get(self.path, self.headers)
            except Exception as e:
                code, obj = 500, {"error": str(e)}
            self._json(code, obj)
        else:
            self._json(404, {"error": "not found"})

    def _client_ip(self):
        return (self.headers.get("CF-Connecting-IP")
                or (self.headers.get("X-Forwarded-For") or "").split(",")[0].strip()
                or self.client_address[0])

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", self._cors_origin())
        self.send_header("Vary", "Origin")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
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
            elif path == "/store/upload":
                code, obj = store_upload(self.headers, raw)
            elif path.startswith("/store/"):
                try:
                    body = json.loads(raw or b"{}")
                except Exception:
                    self._json(400, {"error": "bad json"})
                    return
                code, obj = store_post(path, body, self.headers, ip)
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
                  {"from": "MAX编程社区 <noreply@maxmzh.com>", "to": [email],
                   "subject": "【MAX编程社区】注册验证码：" + code,
                   "text": "你的 MAX编程社区 注册验证码是：" + code + "\n\n10 分钟内有效，请勿告诉他人。\n如非本人操作，请忽略本邮件。",
                   "html": '<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px">'
                           '<h2 style="color:#4d7cfe;margin:0 0 12px">MAX编程社区 注册验证码</h2>'
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
# ---------------- 应用商店后台（/store/*，自托管 SQLite，MAX 账号鉴权） ----------------
import urllib.parse

_STORE_DB = os.environ.get("MMC_STORE_DB", "/opt/mmc-api/store.db")
_store_lock = threading.Lock()
_STORE_DEFAULT_ANNOUNCE = "欢迎来到 MAX 应用商店安卓版！评论和评分功能已经开放，登录 MAX 账号就能给应用打分、留言。"
_store_last_comment = {}


def _store_conn():
    conn = sqlite3.connect(_STORE_DB, timeout=5)
    conn.execute("CREATE TABLE IF NOT EXISTS comments (id INTEGER PRIMARY KEY AUTOINCREMENT, app TEXT, uid TEXT, username TEXT, content TEXT, created_at TEXT, hidden INTEGER DEFAULT 0, parent INTEGER DEFAULT 0)")
    try:
        cols = [r[1] for r in conn.execute("PRAGMA table_info(comments)").fetchall()]
        if cols and "parent" not in cols:
            conn.execute("ALTER TABLE comments ADD COLUMN parent INTEGER DEFAULT 0")
            conn.commit()
    except Exception:
        pass
    conn.execute("CREATE TABLE IF NOT EXISTS ratings (app TEXT, uid TEXT, score INTEGER, updated_at TEXT, PRIMARY KEY (app, uid))")
    conn.execute("CREATE TABLE IF NOT EXISTS submissions (id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT, username TEXT, name TEXT, url TEXT, category TEXT, desc TEXT, contact TEXT, status TEXT DEFAULT 'pending', created_at TEXT, apk_file TEXT, apk_pkg TEXT, apk_ver TEXT, apk_label TEXT)")
    try:
        scols = [r[1] for r in conn.execute("PRAGMA table_info(submissions)").fetchall()]
        for col in ("apk_file", "apk_pkg", "apk_ver", "apk_label"):
            if scols and col not in scols:
                conn.execute("ALTER TABLE submissions ADD COLUMN " + col + " TEXT")
        conn.commit()
    except Exception:
        pass
    conn.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
    conn.execute("CREATE TABLE IF NOT EXISTS favorites (uid TEXT, app TEXT, created_at TEXT, PRIMARY KEY (uid, app))")
    return conn


def _profile_of(uid):
    try:
        st, rows = _http("GET", SB_URL + "/rest/v1/profiles?id=eq." + uid + "&select=username,is_admin", _svc_headers())
    except Exception:
        return "", False
    if st == 200 and rows:
        return rows[0].get("username") or "", bool(rows[0].get("is_admin"))
    return "", False


def _auth_user(headers):
    auth = headers.get("Authorization") or ""
    token = auth[7:] if auth.startswith("Bearer ") else ""
    if not token:
        return None
    uid = _validate_token(token)
    if not uid:
        return None
    name, admin = _profile_of(uid)
    return {"uid": uid, "username": name, "is_admin": admin}


def _known_apps():
    try:
        with open("/var/www/maxmzh/store-apps.json") as f:
            d = json.load(f)
        names = [a.get("name", "") for a in d.get("apps", [])] + [a.get("name", "") for a in d.get("third", [])]
        return set(n for n in names if n)
    except Exception:
        return None


def _clean(s, maxlen):
    s = str(s or "").strip()
    s = re.sub(r"[<>\x00-\x08\x0b\x0c\x0e-\x1f]", "", s)
    return s[:maxlen]


def _rating_agg(conn, app, uid=None):
    row = conn.execute("SELECT AVG(score), COUNT(*) FROM ratings WHERE app = ?", (app,)).fetchone()
    avg = round(row[0], 1) if row and row[0] is not None else 0
    cnt = row[1] if row else 0
    dist = [0, 0, 0, 0, 0]
    for sc, n in conn.execute("SELECT score, COUNT(*) FROM ratings WHERE app = ? GROUP BY score", (app,)).fetchall():
        if 1 <= sc <= 5:
            dist[5 - sc] = n
    mine = None
    if uid:
        r2 = conn.execute("SELECT score FROM ratings WHERE app = ? AND uid = ?", (app, uid)).fetchone()
        mine = r2[0] if r2 else None
    return {"avg": avg, "count": cnt, "mine": mine, "dist": dist}


# ---------------- APK 上传与解析（投稿带文件，纯标准库解析二进制清单） ----------------
import io as _io
import struct as _struct
import time as _time
import zipfile as _zipfile

_STORE_UPLOADS = os.environ.get("MMC_STORE_UPLOADS", "/opt/mmc-api/store_uploads")
_STORE_UPLOAD_MAX = 60 * 1024 * 1024


def _sp_strings(data, off):
    """解析 AXML/ARSC 的字符串池分块，返回字符串列表。"""
    _t, _h, _c = _struct.unpack_from("<HHI", data, off)
    scount, _yc, flags, soff, _yo = _struct.unpack_from("<IIIII", data, off + 8)
    utf8 = bool(flags & 0x100)
    offs = [_struct.unpack_from("<I", data, off + _h + i * 4)[0] for i in range(scount)]
    base = off + soff
    out = []
    for o in offs:
        p = base + o
        if utf8:
            def _u8len(p):
                b0 = data[p]
                if b0 & 0x80:
                    return ((b0 & 0x7F) << 8) | data[p + 1], p + 2
                return b0, p + 1
            _n, p = _u8len(p)
            blen, p = _u8len(p)
            out.append(data[p:p + blen].decode("utf-8", "replace"))
        else:
            ln = _struct.unpack_from("<H", data, p)[0]
            p += 2
            if ln & 0x8000:
                ln2 = _struct.unpack_from("<H", data, p)[0]
                p += 2
                ln = ((ln & 0x7FFF) << 16) | ln2
            out.append(data[p:p + ln * 2].decode("utf-16-le", "replace"))
    return out


def _axml_parse(axml):
    """返回 {package, version_name, version_code, label, label_ref}（取不到为 None）。"""
    info = {"package": None, "version_name": None, "version_code": None, "label": None, "label_ref": None}
    if len(axml) < 8:
        return info
    strings = []
    pos = 8
    while pos + 8 <= len(axml):
        ctype, _h, csize = _struct.unpack_from("<HHI", axml, pos)
        if csize < 8:
            break
        if ctype == 0x0001:
            try:
                strings = _sp_strings(axml, pos)
            except Exception:
                strings = []
        elif ctype == 0x0102 and strings:
            try:
                _ns, name_i, astart, asize, acount = _struct.unpack_from("<IIHHH", axml, pos + 16)
                ename = strings[name_i] if 0 <= name_i < len(strings) else ""
                abase = pos + 16 + astart
                for i in range(acount):
                    ap = abase + i * asize
                    if ap + 20 > len(axml):
                        break
                    _ans, an_i, raw_i, = _struct.unpack_from("<IIi", axml, ap)
                    vsize, _z, dtype = _struct.unpack_from("<HBb", axml, ap + 12)
                    vdata = _struct.unpack_from("<I", axml, ap + 16)[0]
                    aname = strings[an_i] if 0 <= an_i < len(strings) else ""
                    def _s(idx):
                        return strings[idx] if 0 <= idx < len(strings) else None
                    raw = _s(raw_i) if raw_i >= 0 else None
                    if ename == "manifest":
                        if aname == "package":
                            info["package"] = raw or _s(vdata)
                        elif aname == "versionName":
                            info["version_name"] = raw or (_s(vdata) if dtype == 0x03 else None)
                        elif aname == "versionCode":
                            info["version_code"] = vdata if dtype == 0x10 else (int(raw) if raw and raw.isdigit() else None)
                    elif ename == "application" and aname == "label":
                        if raw:
                            info["label"] = raw
                        elif dtype == 0x03:
                            info["label"] = _s(vdata)
                        elif dtype == 0x01:
                            info["label_ref"] = vdata
            except Exception:
                pass
        pos += csize
    return info


def _arsc_string(arsc, resid):
    """在 resources.arsc 里按资源 id 找字符串值（尽力而为）。"""
    try:
        strings = []
        type_id = (resid >> 16) & 0xFF
        entry_idx = resid & 0xFFFF
        pos = _struct.unpack_from("<H", arsc, 2)[0] or 12
        while pos + 8 <= len(arsc):
            ctype, hsize, csize = _struct.unpack_from("<HHI", arsc, pos)
            if csize < 8:
                break
            if ctype == 0x0001 and not strings:
                strings = _sp_strings(arsc, pos)
            elif ctype == 0x0200:
                # package 分块：子分块从 headerSize 处开始
                sub = pos + hsize
                end = pos + csize
                while sub + 8 <= end:
                    st, sh, sc = _struct.unpack_from("<HHI", arsc, sub)
                    if sc < 8:
                        break
                    if st == 0x0201:
                        tid = arsc[sub + 8]
                        if tid == type_id:
                            ecount, estart = _struct.unpack_from("<II", arsc, sub + 12)
                            if entry_idx < ecount:
                                eoff = _struct.unpack_from("<I", arsc, sub + sh + entry_idx * 4)[0]
                                if eoff != 0xFFFFFFFF:
                                    ep = sub + estart + eoff
                                    esize, eflags = _struct.unpack_from("<HH", arsc, ep)
                                    if not (eflags & 0x0001):
                                        _vs, _vz, vtype = _struct.unpack_from("<HBb", arsc, ep + esize)
                                        vdata = _struct.unpack_from("<I", arsc, ep + esize + 4)[0]
                                        if vtype == 0x03 and vdata < len(strings):
                                            return strings[vdata]
                    sub += sc
            pos += csize
    except Exception:
        return None
    return None


def _apk_info(data):
    with _zipfile.ZipFile(_io.BytesIO(data)) as z:
        names = set(z.namelist())
        if "AndroidManifest.xml" not in names:
            raise ValueError("no manifest")
        info = _axml_parse(z.read("AndroidManifest.xml"))
        if not info["label"] and info.get("label_ref") and "resources.arsc" in names:
            info["label"] = _arsc_string(z.read("resources.arsc"), info["label_ref"])
        info.pop("label_ref", None)
        return info


def store_upload(headers, raw):
    me = _auth_user(headers)
    if not me:
        return 401, {"error": "请先登录 MAX 账号"}
    if not raw:
        return 400, {"error": "没收到文件"}
    if len(raw) > _STORE_UPLOAD_MAX:
        return 400, {"error": "APK 太大（上限 60MB）"}
    if raw[:2] != b"PK":
        return 400, {"error": "这不是有效的 APK 文件"}
    try:
        info = _apk_info(raw)
    except Exception:
        return 400, {"error": "APK 解析失败，文件可能损坏或不是安卓安装包"}
    if not info.get("package"):
        return 400, {"error": "APK 里读不到包名，换一个文件试试"}
    os.makedirs(_STORE_UPLOADS, exist_ok=True)
    fname = "%s_%d_%s.apk" % (me["uid"][:13], int(_time.time()), _secrets.token_hex(3))
    fpath = os.path.join(_STORE_UPLOADS, fname)
    with open(fpath, "wb") as f:
        f.write(raw)
    meta = {"info": info, "size": len(raw), "uid": me["uid"], "ts": int(_time.time())}
    with open(fpath + ".json", "w", encoding="utf-8") as f:
        f.write(json.dumps(meta, ensure_ascii=False))
    return 200, {"file": fname, "size": len(raw), "info": info}


def _upload_info_for(uid, fname):
    """校验上传文件归属并读回解析信息；不合法返回 None。"""
    try:
        if not fname or "/" in fname or "\\" in fname or ".." in fname:
            return None
        mpath = os.path.join(_STORE_UPLOADS, fname + ".json")
        with open(mpath, encoding="utf-8") as f:
            meta = json.loads(f.read())
        if meta.get("uid") != uid:
            return None
        return meta.get("info") or {}
    except Exception:
        return None


def store_submission_file(headers, fullpath):
    """管理员下载投稿附带的 APK 试装。返回 (code, bytes|None, filename|error)。"""
    me = _auth_user(headers)
    if not me:
        return 401, None, "请先登录 MAX 账号"
    if not me["is_admin"]:
        return 403, None, "需要管理员账号"
    q = {}
    if "?" in fullpath:
        for part in fullpath.split("?", 1)[1].split("&"):
            if "=" in part:
                k, v = part.split("=", 1)
                q[k] = v
    try:
        sid = int(q.get("id") or 0)
    except Exception:
        sid = 0
    if sid <= 0:
        return 400, None, "缺少投稿编号"
    with _store_lock:
        conn = _store_conn()
        try:
            row = conn.execute("SELECT apk_file, name FROM submissions WHERE id = ?", (sid,)).fetchone()
        finally:
            conn.close()
    if not row or not row[0]:
        return 404, None, "这条投稿没有附带 APK"
    fname = row[0]
    if "/" in fname or ".." in fname:
        return 400, None, "文件名不合法"
    fpath = os.path.join(_STORE_UPLOADS, fname)
    try:
        with open(fpath, "rb") as f:
            data = f.read()
    except Exception:
        return 404, None, "文件已不存在"
    dl_name = (row[1] or "app") + ".apk"
    from urllib.parse import quote as _q
    return 200, data, _q(dl_name)


def store_get(fullpath, headers):
    u = urllib.parse.urlparse(fullpath)
    path = u.path
    q = urllib.parse.parse_qs(u.query)
    app = _clean((q.get("app") or [""])[0], 60)
    if path == "/store/announcement":
        with _store_lock:
            conn = _store_conn()
            try:
                row = conn.execute("SELECT value FROM meta WHERE key = 'announcement'").fetchone()
            finally:
                conn.close()
        return 200, {"text": row[0] if row else _STORE_DEFAULT_ANNOUNCE}
    if path == "/store/me":
        me = _auth_user(headers)
        if not me:
            return 401, {"error": "请先登录 MAX 账号"}
        return 200, me
    if path == "/store/comments":
        if not app:
            return 400, {"error": "缺少 app 参数"}
        try:
            limit = max(1, min(100, int((q.get("limit") or ["50"])[0])))
        except Exception:
            limit = 50
        me = _auth_user(headers)
        with _store_lock:
            conn = _store_conn()
            try:
                rows = conn.execute(
                    "SELECT c.id, c.username, c.content, c.created_at, c.uid, c.parent, "
                    "(SELECT p.username FROM comments p WHERE p.id = c.parent) FROM comments c "
                    "WHERE c.app = ? AND c.hidden = 0 ORDER BY c.id DESC LIMIT ?", (app, limit)).fetchall()
            finally:
                conn.close()
        out = [{"id": r[0], "username": r[1], "content": r[2], "created_at": r[3],
                "mine": bool(me and r[4] == me["uid"]), "parent": r[5] or 0,
                "puser": r[6] or ""} for r in rows]
        return 200, {"comments": out}
    if path == "/store/rating":
        if not app:
            return 400, {"error": "缺少 app 参数"}
        me = _auth_user(headers)
        with _store_lock:
            conn = _store_conn()
            try:
                agg = _rating_agg(conn, app, me["uid"] if me else None)
            finally:
                conn.close()
        return 200, agg
    if path == "/store/favorites":
        me = _auth_user(headers)
        if not me:
            return 401, {"error": "请先登录 MAX 账号"}
        with _store_lock:
            conn = _store_conn()
            try:
                rows = conn.execute("SELECT app FROM favorites WHERE uid = ? ORDER BY created_at", (me["uid"],)).fetchall()
            finally:
                conn.close()
        return 200, {"favorites": [r[0] for r in rows]}
    if path == "/store/my/comments":
        me = _auth_user(headers)
        if not me:
            return 401, {"error": "请先登录 MAX 账号"}
        with _store_lock:
            conn = _store_conn()
            try:
                rows = conn.execute(
                    "SELECT id, app, content, created_at FROM comments "
                    "WHERE uid = ? AND hidden = 0 ORDER BY id DESC LIMIT 100", (me["uid"],)).fetchall()
            finally:
                conn.close()
        out = [{"id": r[0], "app": r[1], "content": r[2], "created_at": r[3]} for r in rows]
        return 200, {"comments": out}
    if path == "/store/top-rated":
        with _store_lock:
            conn = _store_conn()
            try:
                rows = conn.execute(
                    "SELECT app, AVG(score), COUNT(*) FROM ratings GROUP BY app "
                    "HAVING COUNT(*) >= 1 ORDER BY AVG(score) DESC, COUNT(*) DESC LIMIT 10").fetchall()
            finally:
                conn.close()
        return 200, {"top": [{"app": r[0], "avg": round(r[1], 1), "count": r[2]} for r in rows]}
    if path == "/store/submissions":
        me = _auth_user(headers)
        if not me or not me["is_admin"]:
            return 403, {"error": "需要管理员账号"}
        status = _clean((q.get("status") or ["pending"])[0], 20) or "pending"
        with _store_lock:
            conn = _store_conn()
            try:
                rows = conn.execute(
                    "SELECT id, username, name, url, category, desc, contact, status, created_at, apk_file, apk_pkg, apk_ver, apk_label "
                    "FROM submissions WHERE status = ? ORDER BY id DESC LIMIT 100", (status,)).fetchall()
            finally:
                conn.close()
        out = [{"id": r[0], "username": r[1], "name": r[2], "url": r[3], "category": r[4],
                "desc": r[5], "contact": r[6], "status": r[7], "created_at": r[8],
                "apk_file": r[9], "apk_pkg": r[10], "apk_ver": r[11], "apk_label": r[12]} for r in rows]
        return 200, {"submissions": out}
    return 404, {"error": "not found"}


def store_post(path, b, headers, ip):
    if path == "/store/comment":
        me = _auth_user(headers)
        if not me:
            return 401, {"error": "请先登录 MAX 账号"}
        app = _clean(b.get("app"), 60)
        content = _clean(b.get("content"), 300)
        if not app or not content:
            return 400, {"error": "评论不能为空"}
        known = _known_apps()
        if known is not None and app not in known:
            return 400, {"error": "应用不存在"}
        try:
            parent = int(b.get("parent") or 0)
        except Exception:
            parent = 0
        now = datetime.now(timezone.utc)
        with _store_lock:
            if parent > 0:
                conn0 = _store_conn()
                try:
                    prow = conn0.execute("SELECT app FROM comments WHERE id = ? AND hidden = 0", (parent,)).fetchone()
                finally:
                    conn0.close()
                if not prow or prow[0] != app:
                    return 400, {"error": "回复的评论不存在"}
            last = _store_last_comment.get(me["uid"], 0)
            if now.timestamp() - last < 5:
                return 429, {"error": "发太快了，歇 5 秒再发"}
            _store_last_comment[me["uid"]] = now.timestamp()
            conn = _store_conn()
            try:
                cur = conn.execute(
                    "INSERT INTO comments (app, uid, username, content, created_at, parent) VALUES (?, ?, ?, ?, ?, ?)",
                    (app, me["uid"], me["username"], content, now.isoformat(), parent))
                conn.commit()
                cid = cur.lastrowid
            finally:
                conn.close()
        return 200, {"id": cid, "username": me["username"], "content": content,
                     "created_at": now.isoformat(), "mine": True}
    if path == "/store/rate":
        me = _auth_user(headers)
        if not me:
            return 401, {"error": "请先登录 MAX 账号"}
        app = _clean(b.get("app"), 60)
        try:
            score = int(b.get("score"))
        except Exception:
            return 400, {"error": "评分不合法"}
        if not app or score < 0 or score > 5:
            return 400, {"error": "评分不合法"}
        known = _known_apps()
        if known is not None and app not in known:
            return 400, {"error": "应用不存在"}
        with _store_lock:
            conn = _store_conn()
            try:
                if score == 0:
                    conn.execute("DELETE FROM ratings WHERE app = ? AND uid = ?", (app, me["uid"]))
                else:
                    conn.execute(
                        "INSERT INTO ratings (app, uid, score, updated_at) VALUES (?, ?, ?, ?) "
                        "ON CONFLICT(app, uid) DO UPDATE SET score = excluded.score, updated_at = excluded.updated_at",
                        (app, me["uid"], score, datetime.now(timezone.utc).isoformat()))
                conn.commit()
                agg = _rating_agg(conn, app, me["uid"])
            finally:
                conn.close()
        return 200, agg
    if path == "/store/comment/delete":
        me = _auth_user(headers)
        if not me:
            return 401, {"error": "请先登录 MAX 账号"}
        try:
            cid = int(b.get("id"))
        except Exception:
            return 400, {"error": "缺少评论 id"}
        with _store_lock:
            conn = _store_conn()
            try:
                row = conn.execute("SELECT uid FROM comments WHERE id = ?", (cid,)).fetchone()
                if not row:
                    return 404, {"error": "评论不存在"}
                if row[0] != me["uid"] and not me["is_admin"]:
                    return 403, {"error": "只能删自己的评论"}
                conn.execute("UPDATE comments SET hidden = 1 WHERE id = ?", (cid,))
                conn.commit()
            finally:
                conn.close()
        return 200, {"ok": True}
    if path == "/store/submit":
        me = _auth_user(headers)
        if not me:
            return 401, {"error": "请先登录 MAX 账号"}
        name = _clean(b.get("name") or b.get("title"), 60)
        url = _clean(b.get("url"), 300)
        category = _clean(b.get("category"), 20)
        desc = _clean(b.get("desc") or b.get("body"), 500)
        contact = _clean(b.get("contact"), 100)
        apk_file = apk_pkg = apk_ver = apk_label = None
        fname = _clean(b.get("file"), 120)
        if fname:
            info = _upload_info_for(me["uid"], fname)
            if not info:
                return 400, {"error": "上传的 APK 文件不存在或不属于你"}
            apk_file = fname
            apk_pkg = info.get("package")
            apk_ver = info.get("version_name")
            apk_label = info.get("label")
            if not name and apk_label:
                name = apk_label
        if not name or not desc or (not apk_file and not (url.startswith("http://") or url.startswith("https://"))):
            return 400, {"error": "名称、介绍都要填，链接（http 开头）或 APK 文件二选一"}
        with _store_lock:
            conn = _store_conn()
            try:
                cur = conn.execute(
                    "INSERT INTO submissions (uid, username, name, url, category, desc, contact, created_at, apk_file, apk_pkg, apk_ver, apk_label) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (me["uid"], me["username"], name, url, category, desc, contact,
                     datetime.now(timezone.utc).isoformat(), apk_file, apk_pkg, apk_ver, apk_label))
                conn.commit()
                sid = cur.lastrowid
            finally:
                conn.close()
        return 200, {"id": sid, "status": "pending"}
    if path == "/store/favorites":
        me = _auth_user(headers)
        if not me:
            return 401, {"error": "请先登录 MAX 账号"}
        favs = b.get("favorites")
        if not isinstance(favs, list):
            return 400, {"error": "收藏格式不对"}
        clean = []
        for f in favs[:200]:
            f = _clean(f, 60)
            if f and f not in clean:
                clean.append(f)
        with _store_lock:
            conn = _store_conn()
            try:
                conn.execute("DELETE FROM favorites WHERE uid = ?", (me["uid"],))
                now = datetime.now(timezone.utc).isoformat()
                for f in clean:
                    conn.execute("INSERT OR IGNORE INTO favorites (uid, app, created_at) VALUES (?, ?, ?)",
                                 (me["uid"], f, now))
                conn.commit()
            finally:
                conn.close()
        return 200, {"favorites": clean}
    if path == "/store/submission/review":
        me = _auth_user(headers)
        if not me or not me["is_admin"]:
            return 403, {"error": "需要管理员账号"}
        try:
            sid = int(b.get("id"))
        except Exception:
            return 400, {"error": "缺少投稿 id"}
        status = _clean(b.get("status"), 20)
        if status not in ("approved", "rejected", "pending"):
            return 400, {"error": "状态不合法"}
        with _store_lock:
            conn = _store_conn()
            try:
                conn.execute("UPDATE submissions SET status = ? WHERE id = ?", (status, sid))
                conn.commit()
            finally:
                conn.close()
        return 200, {"ok": True, "status": status}
    if path == "/store/submission/delete":
        me = _auth_user(headers)
        if not me or not me["is_admin"]:
            return 403, {"error": "需要管理员账号"}
        try:
            sid = int(b.get("id"))
        except Exception:
            return 400, {"error": "缺少投稿 id"}
        with _store_lock:
            conn = _store_conn()
            try:
                conn.execute("DELETE FROM submissions WHERE id = ?", (sid,))
                conn.commit()
            finally:
                conn.close()
        return 200, {"ok": True}
    if path == "/store/announce":
        me = _auth_user(headers)
        if not me or not me["is_admin"]:
            return 403, {"error": "需要管理员账号"}
        text = _clean(b.get("text"), 300)
        with _store_lock:
            conn = _store_conn()
            try:
                conn.execute(
                    "INSERT INTO meta (key, value) VALUES ('announcement', ?) "
                    "ON CONFLICT(key) DO UPDATE SET value = excluded.value", (text,))
                conn.commit()
            finally:
                conn.close()
        return 200, {"ok": True, "text": text}
    return 404, {"error": "not found"}


if __name__ == "__main__":
    import threading
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print(f"mmc-api listening on 127.0.0.1:{PORT}", flush=True)
    asyncio.run(_ws_main())
