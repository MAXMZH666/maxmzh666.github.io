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
        'community-auth.html': 'auth'
    };
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
var VIRUSTOTAL_API_KEY = '914117b68a34bade04a91ee6e710baf17805a5e604546047b2c08c135309e3c2';
async function vtCheck(file) {
    if (!VIRUSTOTAL_API_KEY) return { status: 'skipped' };
    try {
        var buf = await file.arrayBuffer();
        var digest = await crypto.subtle.digest('SHA-256', buf);
        var hash = Array.from(new Uint8Array(digest)).map(function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
        var r = await fetch('https://www.virustotal.com/api/v3/files/' + hash, {
            headers: { 'x-apikey': VIRUSTOTAL_API_KEY }
        });
        if (r.status === 404) return { status: 'unknown' };
        if (!r.ok) return { status: 'skipped' };
        var j = await r.json();
        var stats = (((j || {}).data || {}).attributes || {}).last_analysis_stats || {};
        var mal = stats.malicious || 0, sus = stats.suspicious || 0;
        if (mal > 0 || sus > 0) return { status: 'malicious', detail: mal + ' 家检出病毒 / ' + sus + ' 家可疑' };
        return { status: 'clean' };
    } catch (e) { return { status: 'skipped' }; }
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

