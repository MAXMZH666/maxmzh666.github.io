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
        var r = await window.sb.from('profiles').select('username').eq('id', u.id).single();
        if (r.data && r.data.username) username = r.data.username;
    } catch (e) {}
    return { id: u.id, email: u.email, username: username };
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
    apk:     { name: 'APK',     icon: '📱' }
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
