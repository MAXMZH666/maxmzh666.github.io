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

/* 导航栏登录状态（仅社区页面有 #nav-auth） */
async function renderNavAuth() {
    var el = document.getElementById('nav-auth');
    if (!el) return;
    var p = await currentProfile();
    if (p) {
        el.innerHTML = '<span class="nav-user">' + esc(p.username) + '</span>' +
            '<a href="#" id="nav-logout">退出</a>';
        document.getElementById('nav-logout').addEventListener('click', async function (e) {
            e.preventDefault();
            await window.sb.auth.signOut();
            location.reload();
        });
    } else {
        var next = encodeURIComponent(location.pathname.split('/').pop() + location.search);
        el.innerHTML = '<a href="community-auth.html?next=' + next + '">登录</a>';
    }
}

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
