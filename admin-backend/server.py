#!/usr/bin/env python3
"""MAXMZH 网站后台服务（纯 Python 标准库，无第三方依赖）。

功能：管理员登录、首页「最新消息」编辑、访问统计（解析 nginx 日志）、服务器状态。
数据目录：/opt/maxmzh-admin/data（可用环境变量覆盖）
  - auth.json       密码哈希 + 会话密钥（首次设置后生成）
  - setup-token.txt 一次性设置码（设置完成后删除）
  - data.json       新闻数据
监听：127.0.0.1:8790（由 nginx 反向代理 /api/ 与 /admin/）
"""
import gzip
import hashlib
import hmac
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.environ.get("ADMIN_DATA_DIR", "/opt/maxmzh-admin/data")
PORT = int(os.environ.get("ADMIN_PORT", "8790"))
ACCESS_LOG = os.environ.get("ADMIN_ACCESS_LOG", "/var/log/nginx/access.log")
SITE_DIR = os.environ.get("ADMIN_SITE_DIR", "/var/www/maxmzh")
INSECURE_COOKIE = os.environ.get("ADMIN_INSECURE_COOKIE", "") == "1"
SESSION_TTL = 7 * 24 * 3600

AUTH_FILE = os.path.join(DATA_DIR, "auth.json")
TOKEN_FILE = os.path.join(DATA_DIR, "setup-token.txt")
DATA_FILE = os.path.join(DATA_DIR, "data.json")

SEED_NEWS = [
    {"date": "2026-10-10", "title": "🛠️ 网站工具矩阵上线",
     "text": "网络工具、MAX 打包工具免费在线用，AI 编程助手填入自己的 API Key 即可用，入口都在页面底部工具栏。",
     "link": None},
    {"date": "2026-10-02", "title": "🎮 MAX社区正式上线",
     "text": "分享 Scratch、Python、C++、APK 作品，在线试玩、评论点赞、论坛灌水，欢迎加入！",
     "link": None},
    {"date": "2026-10", "title": "📦 MAX 打包工具发布",
     "text": "自托管打包服务：一键把 Scratch 作品转成 HTML / ZIP / 可执行文件。",
     "link": None},
    {"date": "2026-09", "title": "🎯《审判行动：致命瞄准》持续更新",
     "text": "射击手感与画面表现全面打磨，",
     "link": {"text": "在线试玩 →", "url": "community-play.html?id=eebe7a42-5536-4fe7-b65f-570221e06057"}},
]

_login_fails = {}  # ip -> [timestamps]


def _load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def _save_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def _hash_password(password, salt=None):
    salt = salt or secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 200_000)
    return salt.hex() + "$" + dk.hex()


def _check_password(password, stored):
    try:
        salt_hex, _ = stored.split("$", 1)
        return hmac.compare_digest(_hash_password(password, bytes.fromhex(salt_hex)), stored)
    except Exception:
        return False


def _auth():
    return _load_json(AUTH_FILE, None)


def _sign_session(secret):
    payload = json.dumps({"exp": int(time.time()) + SESSION_TTL}).encode()
    sig = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
    import base64
    return base64.urlsafe_b64encode(payload).decode() + "." + sig


def _verify_session(cookie_val):
    auth = _auth()
    if not auth or not cookie_val or "." not in cookie_val:
        return False
    import base64
    b64, sig = cookie_val.rsplit(".", 1)
    try:
        payload = base64.urlsafe_b64decode(b64.encode())
    except Exception:
        return False
    expect = hmac.new(auth["secret"].encode(), payload, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, expect):
        return False
    try:
        return json.loads(payload)["exp"] > int(time.time())
    except Exception:
        return False


def _news():
    data = _load_json(DATA_FILE, None)
    if not data or "news" not in data:
        return list(SEED_NEWS)
    return data["news"]


LOG_RE = re.compile(
    r'^(\S+)\s+\S+\s+\S+\s+\[([^\]]+)\]\s+"(\S+)\s+(\S+)[^"]*"\s+(\d{3})\s+'
)
MONTHS = {m: i + 1 for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])}


def _parse_log_day(timestr):
    # 13/Nov/2026:19:01:02 +0800
    try:
        d, mon, rest = timestr.split("/", 2)
        y = int(rest[:4])
        return "%04d-%02d-%02d" % (y, MONTHS[mon], int(d))
    except Exception:
        return None


def _is_page(path):
    p = path.split("?")[0]
    if p in ("/", ""):
        return True
    if "." not in p.rsplit("/", 1)[-1]:
        return True
    return p.endswith(".html")


def compute_stats():
    days = {}
    pages = {}
    files = [ACCESS_LOG, ACCESS_LOG + ".1", ACCESS_LOG + ".gz", ACCESS_LOG + ".1.gz"]
    for path in files:
        try:
            opener = gzip.open if path.endswith(".gz") else open
            with opener(path, "rt", encoding="utf-8", errors="replace") as f:
                for line in f:
                    m = LOG_RE.match(line)
                    if not m:
                        continue
                    ip, ts, method, pth, status = m.groups()
                    day = _parse_log_day(ts)
                    if not day:
                        continue
                    # PV/UV 只统计成功打开的页面请求，不含 CSS/JS/图片等资源请求
                    if method != "GET" or not status.startswith(("2", "3")) or not _is_page(pth):
                        continue
                    slot = days.setdefault(day, {"pv": 0, "ips": set()})
                    slot["pv"] += 1
                    slot["ips"].add(ip)
                    if status.startswith("2"):
                        key = pth.split("?")[0]
                        pages[key] = pages.get(key, 0) + 1
        except FileNotFoundError:
            continue
        except Exception:
            continue
    today = datetime.now().strftime("%Y-%m-%d")
    last7 = []
    for i in range(6, -1, -1):
        d = (datetime.now() - timedelta(days=i)).strftime("%Y-%m-%d")
        slot = days.get(d, {"pv": 0, "ips": set()})
        last7.append({"date": d, "pv": slot["pv"], "uv": len(slot["ips"])})
    yd = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
    yslot = days.get(yd, {"pv": 0, "ips": set()})
    tslot = days.get(today, {"pv": 0, "ips": set()})
    top = sorted(pages.items(), key=lambda kv: -kv[1])[:10]
    return {
        "today": {"date": today, "pv": tslot["pv"], "uv": len(tslot["ips"])},
        "yesterday": {"date": yd, "pv": yslot["pv"], "uv": len(yslot["ips"])},
        "last7": last7,
        "top_pages": [{"path": p, "pv": c} for p, c in top],
        "total_days_recorded": len(days),
    }


_stats_cache = {"at": 0.0, "data": None}
STATS_TTL = 120  # 访问统计缓存秒数：日志只增不改，短时缓存避免每次打开后台都全量解析


def compute_stats_cached():
    now = time.time()
    if _stats_cache["data"] is not None and now - _stats_cache["at"] < STATS_TTL:
        return _stats_cache["data"]
    data = compute_stats()
    data["cached_at"] = datetime.now().strftime("%H:%M:%S")
    _stats_cache["at"] = now
    _stats_cache["data"] = data
    return data


def server_status():
    out = {}
    try:
        out["load"] = [round(x, 2) for x in os.getloadavg()]
        out["cpu_count"] = os.cpu_count() or 1
    except Exception:
        out["load"] = []
    try:
        mem = {}
        with open("/proc/meminfo") as f:
            for line in f:
                k, v = line.split(":", 1)
                mem[k.strip()] = int(v.split()[0])
        total = mem.get("MemTotal", 0)
        avail = mem.get("MemAvailable", 0)
        out["mem"] = {"total_mb": total // 1024, "used_mb": (total - avail) // 1024,
                      "pct": round((total - avail) * 100 / total, 1) if total else 0}
    except Exception:
        out["mem"] = {}
    try:
        du = shutil.disk_usage("/")
        out["disk"] = {"total_gb": round(du.total / 1e9, 1), "used_gb": round(du.used / 1e9, 1),
                       "pct": round(du.used * 100 / du.total, 1) if du.total else 0}
    except Exception:
        out["disk"] = {}
    try:
        with open("/proc/uptime") as f:
            out["uptime_hours"] = round(float(f.read().split()[0]) / 3600, 1)
    except Exception:
        out["uptime_hours"] = None
    try:
        r = subprocess.run(["systemctl", "is-active", "nginx"], capture_output=True, text=True, timeout=5)
        out["nginx"] = r.stdout.strip() or "unknown"
    except Exception:
        out["nginx"] = "unknown"
    try:
        h = subprocess.run(["git", "-C", SITE_DIR, "log", "-1", "--format=%h|%ci"],
                           capture_output=True, text=True, timeout=5)
        parts = h.stdout.strip().split("|")
        out["site_commit"] = parts[0] if parts and parts[0] else "unknown"
        out["site_commit_time"] = parts[1][:16] if len(parts) > 1 else ""
    except Exception:
        out["site_commit"] = "unknown"
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "MaxAdmin/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    # ---------- helpers ----------
    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return {}

    def _client_ip(self):
        return self.headers.get("X-Real-IP") or self.address_string()

    def _authed(self):
        cookie = self.headers.get("Cookie") or ""
        val = None
        for part in cookie.split(";"):
            part = part.strip()
            if part.startswith("mzadmin="):
                val = part[len("mzadmin="):]
        return _verify_session(val)

    def _set_cookie(self, val, max_age):
        auth = "Secure; " if not INSECURE_COOKIE else ""
        self.send_header("Set-Cookie",
                         "mzadmin=%s; Path=/; HttpOnly; SameSite=Lax; %sMax-Age=%d" % (val, auth, max_age))

    # ---------- routing ----------
    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/news":
            return self._json(200, {"items": _news()})
        if path in ("/admin", "/admin/"):
            return self._admin_page()
        if path == "/api/admin/state":
            if not _auth():
                token = ""
                try:
                    token = open(TOKEN_FILE).read().strip()
                except Exception:
                    pass
                return self._json(200, {"setup": bool(token), "authed": False})
            return self._json(200, {"setup": False, "authed": self._authed()})
        if path == "/api/admin/news":
            if not self._authed():
                return self._json(401, {"error": "未登录"})
            return self._json(200, {"items": _news()})
        if path == "/api/admin/stats":
            if not self._authed():
                return self._json(401, {"error": "未登录"})
            return self._json(200, compute_stats_cached())
        if path == "/api/admin/server":
            if not self._authed():
                return self._json(401, {"error": "未登录"})
            return self._json(200, server_status())
        return self._json(404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/setup":
            return self._setup()
        if path == "/api/login":
            return self._login()
        if path == "/api/logout":
            self.send_response(200)
            self._set_cookie("", 0)
            body = b'{"ok":true}'
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/admin/news":
            if not self._authed():
                return self._json(401, {"error": "未登录"})
            return self._save_news()
        if path == "/api/admin/password":
            if not self._authed():
                return self._json(401, {"error": "未登录"})
            return self._change_password()
        return self._json(404, {"error": "not found"})

    # ---------- actions ----------
    def _admin_page(self):
        try:
            with open(os.path.join(BASE_DIR, "admin.html"), "rb") as f:
                body = f.read()
        except Exception:
            return self._json(500, {"error": "admin.html missing"})
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _setup(self):
        if _auth():
            return self._json(404, {"error": "已完成设置"})
        try:
            token = open(TOKEN_FILE).read().strip()
        except Exception:
            return self._json(404, {"error": "缺少设置码"})
        data = self._body()
        if not data.get("token") or not hmac.compare_digest(str(data["token"]), token):
            return self._json(403, {"error": "设置码不正确"})
        pw = str(data.get("password") or "")
        if len(pw) < 8:
            return self._json(400, {"error": "密码至少 8 位"})
        auth = {"pw": _hash_password(pw), "secret": secrets.token_hex(32)}
        _save_json(AUTH_FILE, auth)
        try:
            os.remove(TOKEN_FILE)
        except Exception:
            pass
        self.send_response(200)
        self._set_cookie(_sign_session(auth["secret"]), SESSION_TTL)
        body = b'{"ok":true}'
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _login(self):
        ip = self._client_ip()
        now = time.time()
        fails = [t for t in _login_fails.get(ip, []) if now - t < 600]
        if len(fails) >= 5:
            return self._json(429, {"error": "尝试次数过多，请 10 分钟后再试"})
        auth = _auth()
        if not auth:
            return self._json(404, {"error": "尚未设置密码"})
        data = self._body()
        if _check_password(str(data.get("password") or ""), auth["pw"]):
            _login_fails.pop(ip, None)
            self.send_response(200)
            self._set_cookie(_sign_session(auth["secret"]), SESSION_TTL)
            body = b'{"ok":true}'
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            fails.append(now)
            _login_fails[ip] = fails
            time.sleep(0.6)
            return self._json(401, {"error": "密码不正确"})

    def _ok_with_cookie(self, secret):
        self.send_response(200)
        self._set_cookie(_sign_session(secret), SESSION_TTL)
        body = b'{"ok":true}'
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _change_password(self):
        auth = _auth()
        if not auth:
            return self._json(404, {"error": "尚未设置密码"})
        data = self._body()
        if not _check_password(str(data.get("current") or ""), auth["pw"]):
            return self._json(401, {"error": "当前密码不正确"})
        new = str(data.get("new") or "")
        if len(new) < 8:
            return self._json(400, {"error": "新密码至少 8 位"})
        if _check_password(new, auth["pw"]):
            return self._json(400, {"error": "新密码不能和当前密码相同"})
        # 换密码同时轮换会话密钥：其他设备上的旧登录立即失效，本机用新会话续上
        auth = {"pw": _hash_password(new), "secret": secrets.token_hex(32)}
        _save_json(AUTH_FILE, auth)
        return self._ok_with_cookie(auth["secret"])

    def _save_news(self):
        data = self._body()
        items = data.get("items")
        if not isinstance(items, list) or len(items) > 20:
            return self._json(400, {"error": "数据格式不对"})
        clean = []
        for it in items:
            if not isinstance(it, dict):
                return self._json(400, {"error": "数据格式不对"})
            date = str(it.get("date") or "")[:20]
            title = str(it.get("title") or "")[:120]
            text = str(it.get("text") or "")[:500]
            link = it.get("link")
            clean_link = None
            if isinstance(link, dict) and link.get("url"):
                url = str(link["url"])[:300]
                if re.match(r"^(https?://|/|\./|[A-Za-z0-9_-]+\.html)", url) and "javascript:" not in url.lower():
                    clean_link = {"text": str(link.get("text") or "查看 →")[:40], "url": url}
            if title or text:
                clean.append({"date": date, "title": title, "text": text, "link": clean_link})
        _save_json(DATA_FILE, {"news": clean, "updated_at": int(time.time())})
        return self._json(200, {"ok": True, "count": len(clean)})


def main():
    os.makedirs(DATA_DIR, exist_ok=True)
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("maxmzh-admin listening on 127.0.0.1:%d, data dir %s" % (PORT, DATA_DIR), flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
