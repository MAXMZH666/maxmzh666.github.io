/* ===== MAXMZH 社区：Supabase 初始化与共用工具 ===== */
(function () {
    var SUPABASE_URL = 'https://xkvpzxxtcnocofnsezpy.supabase.co';
    var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhrdnB6eHh0Y25vY29mbnNlenB5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5MTY4MzQsImV4cCI6MjEwNjQ5MjgzNH0.zTpvyEsutA9hV_UIg36g5owBRnxdHaI-sy_fLUsu6ec';
    if (!window.supabase) { console.error('supabase-js 未加载'); return; }
    window.sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
})();

/* HTML 转义，防止 XSS */
function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
}

function fmtDate(iso) {
    var d = new Date(iso);
    function p(n) { return String(n).padStart(2, '0'); }
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
}

async function currentUser() {
    try {
        var r = await window.sb.auth.getUser();
        return r.data.user || null;
    } catch (e) { return null; }
}

async function currentProfile() {
    var u = await currentUser();
    if (!u) return null;
    var username = (u.user_metadata && u.user_metadata.username) || u.email.split('@')[0];
    try {
        var r = await window.sb.from('profiles').select('username,is_admin').eq('id', u.id).single();
        if (r.data && r.data.username) username = r.data.username;
        if (r.data) isAdminFlag = !!r.data.is_admin;
    } catch (e) {}
    return { id: u.id, email: u.email, username: username, is_admin: isAdminFlag };
}
var isAdminFlag = false;
async function isAdmin() {
    await currentProfile();
    return isAdminFlag;
}

/* ===== 社区 v4：独立子页眉 ===== */
async function renderSubHeader() {
    var authEl = document.getElementById('sub-auth');
    var bellEl = document.getElementById('sub-bell');
    var page = location.pathname.split('/').pop();
    var map = {
        'community.html': 'home',
        'community-publish.html': 'publish',
        'community-code.html': 'code',
        'community-rank.html': 'rank',
        'community-notify.html': 'notify',
        'community-user.html': 'mine',
        'community-auth.html': 'auth',
        'community-forum.html': 'forum',
        'community-thread.html': 'forum',
        'community-forum-new.html': 'forum'
    };
    /* 论坛入口注入：插到"发布作品"后面 */
    try {
        var _fnav = document.querySelector('.sub-links');
        if (_fnav && !_fnav.querySelector('[data-sub="forum"]')) {
            var _fa = document.createElement('a');
            _fa.href = 'community-forum.html';
            _fa.setAttribute('data-sub', 'forum');
            _fa.textContent = '💬 论坛';
            var _pub = _fnav.querySelector('[data-sub="publish"]');
            if (_pub && _pub.nextSibling) _fnav.insertBefore(_fa, _pub.nextSibling);
            else _fnav.appendChild(_fa);
        }
    } catch (e) {}
    document.querySelectorAll('.sub-links a[data-sub]').forEach(function (a) {
        a.classList.toggle('active', a.getAttribute('data-sub') === map[page]);
    });
    try {
        if (p && p.is_admin) {
            var nav = document.querySelector('.sub-links');
            if (nav && !nav.querySelector('[data-sub="admin"]')) {
                var aa = document.createElement('a');
                aa.href = 'community-admin.html';
                aa.setAttribute('data-sub', 'admin');
                aa.textContent = '🛡 管理';
                if (map[page] === undefined && page === 'community-admin.html') aa.classList.add('active');
                nav.appendChild(aa);
            }
        }
    } catch (e) {}
    var p = await currentProfile();
    if (authEl) {
        if (p) {
            authEl.innerHTML = '<a href="community-user.html?id=' + p.id + '">' + esc(p.username) + '</a>' +
                '<a href="#" id="sub-logout">退出</a>';
            document.getElementById('sub-logout').addEventListener('click', async function (e) {
                e.preventDefault();
                await window.sb.auth.signOut();
                location.reload();
            });
        } else {
            var next = encodeURIComponent(page + location.search);
            authEl.innerHTML = '<a href="community-auth.html?next=' + next + '">登录</a>';
        }
    }
    if (bellEl) {
        if (!p) { bellEl.style.display = 'none'; }
        else {
            try {
                var r = await window.sb.from('notifications')
                    .select('id', { count: 'exact', head: true })
                    .eq('user_id', p.id).eq('is_read', false);
                var n = r.count || 0;
                bellEl.innerHTML = '🔔 通知' + (n > 0 ? '<span class="bell-badge">' + (n > 99 ? '99+' : n) + '</span>' : '');
                bellEl.style.display = '';
            } catch (e) { bellEl.innerHTML = '🔔 通知'; bellEl.style.display = ''; }
        }
    }
}
/* 兼容旧调用 */
async function renderNavAuth() { return renderSubHeader(); }
async function renderNavBell() {}

function authRequiredRedirect() {
    var next = encodeURIComponent(location.pathname.split('/').pop() + location.search);
    location.href = 'community-auth.html?next=' + next;
}

/* 确保登录用户在 profiles 表里有一行（注册触发器已移除，由前端保证） */
async function ensureProfile() {
    var u = await currentUser();
    if (!u) return null;
    var base = String((u.user_metadata && u.user_metadata.username) || u.email.split('@')[0] || 'user').slice(0, 20);
    var candidates = [base, base + '_' + u.id.slice(0, 4)];
    for (var i = 0; i < candidates.length; i++) {
        var r = await window.sb.from('profiles').upsert(
            { id: u.id, username: candidates[i] }, { onConflict: 'id' });
        if (!r.error) return { id: u.id, username: candidates[i] };
    }
    return { id: u.id, username: base };
}

if (window.sb) {
    window.sb.auth.onAuthStateChange(function (event, session) {
        if (event === 'SIGNED_IN' && session) { ensureProfile(); }
    });
}

/* ===== 社区 v2：分类、上传优化 ===== */
var WORK_CATEGORIES = ['游戏', '动画', '工具', '音乐', '其他'];

/* ===== 社区 v5：作品类型 ===== */
var WORK_TYPES = {
    scratch: { name: 'Scratch', icon: '🎮' },
    python:  { name: 'Python',  icon: '🐍' },
    cpp:     { name: 'C++',     icon: '⚙️' },
    apk:     { name: 'APK',     icon: '📱' },
    windows: { name: 'Windows', icon: '🪟' },
    linux:   { name: 'Linux',   icon: '🐧' },
    website: { name: '网站',    icon: '🌐' }
};
function workTypeOf(w) {
    var t = w && w.work_type;
    return WORK_TYPES[t] ? t : 'scratch';
}
function typeBadge(t) {
    var m = WORK_TYPES[t] || WORK_TYPES.scratch;
    return '<span class="tag type">' + m.icon + ' ' + m.name + '</span>';
}
/* 动态加载外部脚本（Pyodide / JSCPP 按需加载） */
function loadScriptOnce(src) {
    if (document.querySelector('script[src="' + src + '"]')) return Promise.resolve();
    return new Promise(function (resolve, reject) {
        var s = document.createElement('script');
        s.src = src;
        s.onload = function () { resolve(); };
        s.onerror = function () { reject(new Error('脚本加载失败')); };
        document.head.appendChild(s);
    });
}

/* 带进度的上传：优先用 signed URL + XHR 显示进度，失败回退普通上传 */
async function uploadWithProgress(bucket, path, file, contentType, onProgress) {
    /* R2 优先（10GB 免费），失败回退 Supabase，保证发布不中断 */
    if (R2_WORKER_URL) {
        try {
            return await uploadViaR2(bucket + '/' + path, file, contentType, onProgress);
        } catch (e) {
            try { console.warn('R2 上传失败，回退 Supabase：' + e.message); } catch (e2) {}
        }
    }
    var pub = function () { return window.sb.storage.from(bucket).getPublicUrl(path).data.publicUrl; };
    try {
        var s = await window.sb.storage.from(bucket).createSignedUploadUrl(path);
        if (s.error) throw s.error;
        await new Promise(function (resolve, reject) {
            var xhr = new XMLHttpRequest();
            xhr.open('PUT', s.data.signedUrl);
            if (contentType) xhr.setRequestHeader('Content-Type', contentType);
            xhr.upload.onprogress = function (e) {
                if (e.lengthComputable && onProgress) onProgress(e.loaded / e.total);
            };
            xhr.onload = function () {
                if (xhr.status >= 200 && xhr.status < 300) resolve();
                else reject(new Error('上传失败(' + xhr.status + ')'));
            };
            xhr.onerror = function () { reject(new Error('网络错误，上传中断')); };
            xhr.send(file);
        });
    } catch (e) {
        if (onProgress) onProgress(-1); /* -1 表示进度未知 */
        var up = await window.sb.storage.from(bucket).upload(path, file, { contentType: contentType });
        if (up.error) throw up.error;
    }
    return pub();
}

/* ===== 社区 v3：通知小红点（已并入 renderSubHeader，保留空函数兼容） */

/* ===== VirusTotal 云查杀 =====
   去 https://www.virustotal.com 申请免费 API Key（2 分钟），填到下面即可启用。
   启用后：发布安装包时先查文件 SHA256 是否为已知病毒；命中则拦截发布。 */
var VIRUSTOTAL_API_KEY = ''; /* 已废弃：云查杀改走 Cloudflare Worker，Key 保存在 Worker 机密里 */
async function vtCheck(file) {
    /* 经 Worker 代理（浏览器直调 VT 会被跨域拦截；Key 也藏在 Worker 里） */
    if (!R2_WORKER_URL) return { status: 'skipped' };
    try {
        var buf = await file.arrayBuffer();
        var digest = await crypto.subtle.digest('SHA-256', buf);
        var hash = Array.from(new Uint8Array(digest)).map(function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
        var token = await workerToken();
        var r = await fetch(R2_WORKER_URL + '/vt/' + hash, {
            headers: { 'Authorization': 'Bearer ' + token },
        });
        if (r.status === 401) return { status: 'denied' };
        if (!r.ok) return { status: 'skipped' };
        return await r.json();
    } catch (e) { return { status: 'skipped' }; }
}

/* ===== Cloudflare Worker（R2 存储 + VT 云查杀代理）=====
   Worker 部署好后把地址填到下面。未填时上传走 Supabase、云查杀跳过（原有行为）。 */
var R2_WORKER_URL = 'https://mmc-community.9675036.workers.dev';

async function workerToken() {
    try {
        var s = await window.sb.auth.getSession();
        return (s.data.session && s.data.session.access_token) || '';
    } catch (e) { return ''; }
}

/* R2 预签名直传（带进度），失败时抛错由调用方回退 */
async function uploadViaR2(key, file, contentType, onProgress) {
    var token = await workerToken();
    var r = await fetch(R2_WORKER_URL + '/r2/put-url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
        body: JSON.stringify({ key: key, contentType: contentType || 'application/octet-stream' }),
    });
    if (!r.ok) throw new Error('获取 R2 上传地址失败(' + r.status + ')');
    var u = await r.json();
    if (!u.url) throw new Error('R2 返回异常');
    await new Promise(function (resolve, reject) {
        var xhr = new XMLHttpRequest();
        xhr.open('PUT', u.url);
        if (contentType) xhr.setRequestHeader('Content-Type', contentType);
        xhr.upload.onprogress = function (e) {
            if (e.lengthComputable && onProgress) onProgress(e.loaded / e.total);
        };
        xhr.onload = function () {
            if (xhr.status >= 200 && xhr.status < 300) resolve();
            else reject(new Error('R2 上传失败(' + xhr.status + ')'));
        };
        xhr.onerror = function () { reject(new Error('网络错误，上传中断')); };
        xhr.send(file);
    });
    return u.publicUrl;
}

/* ===== 网页运行器（试玩页 + 在线编程共用） ===== */
var pyodide = null;

function injectHljsTheme() {
    if (document.querySelector('link[data-hljs]')) return;
    var l = document.createElement('link');
    l.rel = 'stylesheet';
    l.setAttribute('data-hljs', '1');
    l.href = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css';
    document.head.appendChild(l);
}

/* Python 网页运行（Pyodide） */
async function runPython(code, inputText, say, append) {
    say('正在加载 Python 环境（首次约 10MB，请稍候）…');
    await loadScriptOnce('https://cdn.jsdelivr.net/pyodide/v0.26.4/full/pyodide.js');
    if (!pyodide) pyodide = await loadPyodide();
    var pos = 0;
    try {
        pyodide.setStdin({ stdin: function () {
            return pos >= inputText.length ? null : inputText.charCodeAt(pos++);
        } });
    } catch (e) {}
    pyodide.setStdout({ batched: function (s) { append(s); } });
    pyodide.setStderr({ batched: function (s) { append(s); } });
    say('运行中…');
    try {
        await pyodide.runPythonAsync(code);
        say('运行结束');
    } catch (e) {
        append('\n[错误] ' + (e && e.message ? e.message : e));
        say('运行出错');
    }
}

/* C++ 网页运行（JSCPP 解释器） */
async function runCpp(code, inputText, say, append) {
    say('正在加载 C++ 运行环境…');
    await loadScriptOnce('https://cdn.jsdelivr.net/gh/felixhao28/JSCPP@gh-pages/dist/JSCPP.es5.min.js');
    if (!window.JSCPP || !JSCPP.run) throw new Error('C++ 环境加载失败');
    say('运行中…');
    var total = 0;
    await new Promise(function (resolve) {
        setTimeout(function () {
            try {
                JSCPP.run(code, inputText, {
                    stdio: { write: function (s) {
                        total += s.length;
                        if (total < 30000) append(s);
                    } }
                });
                if (total >= 30000) append('\n[输出过长，已截断]');
                say('运行结束');
            } catch (e) {
                append('\n[错误] ' + (e && e.message ? e.message : e));
                say('运行出错');
            }
            resolve();
        }, 30);
    });
}

