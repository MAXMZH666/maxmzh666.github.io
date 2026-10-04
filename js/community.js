/* ===== MAXMZH 社区：Supabase 初始化与共用工具 ===== */
(function () {
    var SUPABASE_URL = 'https://xkvpzxxtcnocofnsezpy.supabase.co';
    var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhrdnB6eHh0Y25vY29mbnNlenB5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5MTY4MzQsImV4cCI6MjEwNjQ5MjgzNH0.zTpvyEsutA9hV_UIg36g5owBRnxdHaI-sy_fLUsu6ec';
    if (!window.supabase) { console.error('supabase-js 未加载'); return; }
    window.sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
})();

/* HTML 转义，防止 XSS */
/* 卡片悬停预取：鼠标移到作品卡片上时预取试玩页 HTML */
if (typeof document !== 'undefined') {
    document.addEventListener('mouseover', function (e) {
        var a = e.target && e.target.closest ? e.target.closest('a.card[href*="community-play.html"]') : null;
        if (a && a.href && !a._pf) {
            a._pf = true;
            var l = document.createElement('link');
            l.rel = 'prefetch'; l.href = a.href;
            document.head.appendChild(l);
        }
    });
}
/* 60秒 sessionStorage 查询缓存：列表页高频查询用 */
var _qcache = {};
async function cachedQuery(key, fn, ttlSec) {
    var ttl = (ttlSec || 60) * 1000, now = Date.now();
    try {
        var raw = sessionStorage.getItem('mmc_q_' + key);
        if (raw) {
            var o = JSON.parse(raw);
            if (o && o.t && (now - o.t) < ttl) return o.d;
        }
    } catch (e) {}
    var d = await fn();
    try { sessionStorage.setItem('mmc_q_' + key, JSON.stringify({ t: now, d: d })); } catch (e) {}
    return d;
}
function skeletonCards(n) {
    var h = '', i, c = n || 4;
    for (i = 0; i < c; i++) {
        h += '<div class="skeleton-card"><div class="skeleton skeleton-cover"></div>' +
            '<div class="skeleton skeleton-line"></div><div class="skeleton skeleton-line short"></div></div>';
    }
    return h;
}
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
    var page = location.pathname.split('/').pop();
    var map = {
        'community-home.html': 'home',
        'community.html': 'works',
        'community-search.html': 'works',
        'community-shop.html': 'shop',
        'community-contests.html': 'contests',
        'community-contest.html': 'contests',
        'community-contest-new.html': 'contests',
        'community-moderation.html': 'moderation',
        'community-studios.html': 'studios',
        'community-studio.html': 'studios',
        'community-studio-new.html': 'studios',
        'community-publish.html': 'publish',
        'community-forum.html': 'forum',
        'community-thread.html': 'forum',
        'community-forum-new.html': 'forum',
        'community-feed.html': 'mine',
        'community-dm.html': 'mine',
        'community-stats.html': 'mine',
        'community-collections.html': 'mine',
        'community-collection.html': 'mine',
        'community-user.html': 'mine',
        'community-settings.html': 'mine',
        'community-profile-edit.html': 'mine',
        'community-auth.html': 'auth'
    };
    /* 子项映射（下拉菜单内高亮） */
    var subitemMap = {
        'community-feed.html': 'feed',
        'community-dm.html': 'dm',
        'community-stats.html': 'stats',
        'community-collections.html': 'collections',
        'community-collection.html': 'collections',
        'community-user.html': 'profile',
        'community-settings.html': 'settings',
        'community-profile-edit.html': 'settings'
    };
    document.querySelectorAll('.sub-links a[data-sub], .sub-links .sub-drop-btn[data-sub]').forEach(function (a) {
        a.classList.toggle('active', a.getAttribute('data-sub') === map[page]);
    });
    document.querySelectorAll('.sub-drop-menu a[data-subitem]').forEach(function (a) {
        a.classList.toggle('active', a.getAttribute('data-subitem') === subitemMap[page]);
    });
    var p = await currentProfile();
    try {
        if (p && p.is_admin) {
            var nav = document.querySelector('.sub-links');
            if (nav && !nav.querySelector('[data-sub="admin"]')) {
                var aa = document.createElement('a');
                aa.href = 'community-admin.html';
                aa.setAttribute('data-sub', 'admin');
                aa.textContent = '🛡 管理';
                if (page === 'community-admin.html') aa.classList.add('active');
                var authSpan = document.getElementById('sub-auth');
                if (authSpan) nav.insertBefore(aa, authSpan); else nav.appendChild(aa);
            }
        }
    } catch (e) {}
    /* 账号下拉菜单（登录后）：用户名 ▾，含动态/私信/数据/合集/主页/设置 */
    var dropMenu = null, dropBtn = null;
    function initDrop() {
        var drop = document.getElementById('sub-account');
        if (!drop) return;
        dropMenu = drop.querySelector('.sub-drop-menu');
        dropBtn = drop.querySelector('.sub-drop-btn');
        if (!dropBtn || drop.dataset.init) return;
        drop.dataset.init = '1';
        dropBtn.addEventListener('click', function (e) {
            e.stopPropagation();
            var open = drop.classList.toggle('open');
            dropBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
            if (open) positionDropMenu();
        });
        document.addEventListener('click', function (e) {
            if (drop.classList.contains('open') && !drop.contains(e.target)) {
                closeDrop();
            }
        });
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' && drop.classList.contains('open')) {
                closeDrop();
            }
        });
        function closeDrop() {
            drop.classList.remove('open');
            dropBtn.setAttribute('aria-expanded', 'false');
            /* 清除 fixed 定位，还原 CSS hover 定位 */
            if (dropMenu) {
                dropMenu.style.position = '';
                dropMenu.style.top = '';
                dropMenu.style.left = '';
                dropMenu.style.right = '';
            }
        }
        window.addEventListener('resize', function () {
            if (drop.classList.contains('open')) positionDropMenu();
        });
    }
    function positionDropMenu() {
        /* 用 fixed 定位，避免被子导航的横向滚动裁掉 */
        var menu = dropMenu;
        if (!menu) return;
        var r = dropBtn.getBoundingClientRect();
        menu.style.position = 'fixed';
        menu.style.top = (r.bottom + 6) + 'px';
        menu.style.left = '';
        menu.style.right = '';
        var w = menu.offsetWidth || 170;
        var left = r.right - w;
        if (left < 8) left = 8;
        if (left + w > window.innerWidth - 8) left = window.innerWidth - w - 8;
        menu.style.left = left + 'px';
    }
    if (authEl) {
        if (p) {
            authEl.innerHTML = '<div class="sub-drop" id="sub-account">' +
                '<button type="button" class="sub-drop-btn" data-sub="mine" aria-haspopup="true" aria-expanded="false">' + esc(p.username) + ' ▾<span id="mine-dot" class="bell-badge" style="display:none"></span></button>' +
                '<div class="sub-drop-menu" role="menu">' +
                '<a href="community-feed.html" data-subitem="feed" role="menuitem">💬 动态</a>' +
                '<a href="community-dm.html" data-subitem="dm" role="menuitem">✉️ 私信</a>' +
                '<a href="community-stats.html" data-subitem="stats" role="menuitem">📊 数据</a>' +
                '<a href="community-user.html?mine=1#collections" data-subitem="collections" role="menuitem">📚 合集</a>' +
                '<a href="community-user.html?id=' + p.id + '" data-subitem="profile" role="menuitem">👤 个人主页</a>' +
                '<a href="community-settings.html" data-subitem="settings" role="menuitem">⚙️ 设置</a>' +
                '</div></div>' +
                '<a href="#" id="sub-logout">退出</a>';
            document.getElementById('sub-logout').addEventListener('click', async function (e) {
                e.preventDefault();
                await window.sb.auth.signOut();
                location.reload();
            });
            initDrop(); /* 账号菜单已生成，现在绑定下拉点击 */
            /* 子项高亮 */
            document.querySelectorAll('.sub-drop-menu a[data-subitem]').forEach(function (a) {
                a.classList.toggle('active', a.getAttribute('data-subitem') === subitemMap[page]);
            });
            var mineBtn = authEl.querySelector('.sub-drop-btn');
            if (mineBtn && subitemMap[page]) mineBtn.classList.add('active');
        } else {
            var next = encodeURIComponent(page + location.search);
            authEl.innerHTML = '<a href="community-auth.html?next=' + next + '">登录</a>';
        }
    }
    /* 合并未读数：通知 + 私信，显示在"我的"按钮上 */
    var mineDot = document.getElementById('mine-dot');
    if (mineDot) {
        if (!p) { mineDot.style.display = 'none'; }
        else {
            try {
                var nr = await window.sb.from('notifications')
                    .select('id', { count: 'exact', head: true })
                    .eq('user_id', p.id).eq('is_read', false);
                var dr = await window.sb.from('direct_messages')
                    .select('id', { count: 'exact', head: true })
                    .eq('receiver_id', p.id).is('read_at', null);
                var total = (nr.count || 0) + (dr.count || 0);
                if (total > 0) {
                    mineDot.textContent = total > 99 ? '99+' : String(total);
                    mineDot.style.display = '';
                } else {
                    mineDot.style.display = 'none';
                }
            } catch (e) { mineDot.style.display = 'none'; }
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
    /* 已有档案直接返回，绝不覆盖用户改过的昵称 */
    try {
        var ex = await window.sb.from('profiles').select('id,username').eq('id', u.id).maybeSingle();
        if (ex.data) return ex.data;
    } catch (e) {}
    var base = String((u.user_metadata && u.user_metadata.username) || u.email.split('@')[0] || 'user').slice(0, 20);
    var candidates = [base, base + '_' + u.id.slice(0, 4)];
    for (var i = 0; i < candidates.length; i++) {
        try {
            /* 只用 INSERT：已存在行会报错而不会覆盖，杜绝任何覆盖昵称的可能 */
            var r = await window.sb.from('profiles').insert({ id: u.id, username: candidates[i] });
            if (!r.error) return { id: u.id, username: candidates[i] };
        } catch (e2) {}
        /* 插入失败（并发已建或昵称占用）→ 读已有档案返回 */
        try {
            var g = await window.sb.from('profiles').select('id,username').eq('id', u.id).maybeSingle();
            if (g.data) return g.data;
        } catch (e3) {}
    }
    return { id: u.id, username: base };
}

if (window.sb) {
    window.sb.auth.onAuthStateChange(function (event, session) {
        if (event === 'SIGNED_IN' && session) { ensureProfile(); }
    });
}

/* ===== 第五期：任务与积分 ===== */
/* 记录任务进度：actionType 见 tasks 表；state-based 的由任务页检查 */
async function recordTaskProgress(actionType, increment) {
    try {
        var me = await currentUser();
        if (!me) return;
        var tr = await window.sb.from('tasks').select('*').eq('action_type', actionType).eq('is_active', true);
        var tasks = tr.data || [];
        if (!tasks.length) return;
        var today = new Date().toISOString().slice(0, 10);
        for (var i = 0; i < tasks.length; i++) {
            var t = tasks[i];
            var isDaily = t.task_type === 'daily';
            var qr = await window.sb.from('user_tasks').select('*')
                .eq('user_id', me.id).eq('task_id', t.id);
            var row = null;
            (qr.data || []).forEach(function (r) {
                if (isDaily ? r.task_date === today : !r.task_date) row = r;
            });
            if (row && row.completed) continue;
            if (!row) {
                var ins = await window.sb.from('user_tasks').insert({
                    user_id: me.id, task_id: t.id, progress: 0,
                    task_date: isDaily ? today : null
                }).select().single();
                if (ins.error || !ins.data) continue;
                row = ins.data;
            }
            var np = Math.min(row.progress + (increment || 1), t.target_count);
            var upd = { progress: np };
            if (np >= t.target_count && !row.completed) {
                upd.completed = true;
                upd.completed_at = new Date().toISOString();
            }
            await window.sb.from('user_tasks').update(upd).eq('id', row.id);
        }
    } catch (e) {}
}
/* 领取任务奖励，返回 {ok, points} */
async function claimTaskReward(userTaskId) {
    try {
        var r = await window.sb.rpc('claim_task_reward', { p_user_task_id: userTaskId });
        if (r.error) return { ok: false, error: r.error.message };
        return { ok: true, points: r.data };
    } catch (e) { return { ok: false }; }
}
/* ===== 第九期：工作室 ===== */
async function myStudioRole(studioId, userId) {
    if (!userId) return null;
    try {
        var r = await window.sb.from('studio_members').select('role').eq('studio_id', studioId).eq('user_id', userId).limit(1);
        return (r.data && r.data.length) ? r.data[0].role : null;
    } catch (e) { return null; }
}
/* ===== 第八期：社区共建 ===== */
async function executeReportVerdict(caseId, verdict) {
    try {
        var r = await window.sb.rpc('execute_report_verdict', { p_case_id: caseId, p_verdict: verdict });
        if (r.error) return { ok: false, error: r.error.message };
        return { ok: true };
    } catch (e) { return { ok: false }; }
}
/* ===== 第七期：赛事中心 ===== */
/* 赛事状态：upcoming/submitting/voting/ended */
function contestStatus(c) {
    var now = Date.now();
    var ss = new Date(c.submit_start).getTime();
    var se = new Date(c.submit_end).getTime();
    var ve = new Date(c.vote_end).getTime();
    if (now < ss) return 'upcoming';
    if (now < se) return 'submitting';
    if (now < ve) return 'voting';
    return 'ended';
}
var CONTEST_STATUS_TEXT = {
    upcoming: '⏳ 即将开始', submitting: '📝 投稿中',
    voting: '🗳️ 投票中', ended: '🏁 已结束'
};
async function settleContest(contestId) {
    try {
        var r = await window.sb.rpc('settle_contest', { p_contest_id: contestId });
        if (r.error) return { ok: false, error: r.error.message };
        return { ok: true };
    } catch (e) { return { ok: false }; }
}
/* ===== 第六期：积分商城 ===== */
async function purchaseShopItem(itemId) {
    try {
        var r = await window.sb.rpc('purchase_shop_item', { p_item_id: itemId });
        if (r.error) return { ok: false, error: r.error.message };
        return { ok: true };
    } catch (e) { return { ok: false }; }
}
async function equipShopItem(itemId) {
    try {
        var r = await window.sb.rpc('equip_shop_item', { p_item_id: itemId });
        if (r.error) return { ok: false, error: r.error.message };
        return { ok: true };
    } catch (e) { return { ok: false }; }
}
async function unequipShopItem(itemId) {
    try {
        var r = await window.sb.rpc('unequip_shop_item', { p_item_id: itemId });
        if (r.error) return { ok: false };
        return { ok: true };
    } catch (e) { return { ok: false }; }
}
/* 获取某用户已装备的物品 {frame, badge, title}，badge 为数组 */
async function equippedItemsOf(userId) {
    var out = { frame: null, badges: [], title: null };
    try {
        var r = await window.sb.from('user_items').select('item_id,shop_items(item_type,item_data,name)')
            .eq('user_id', userId).eq('is_equipped', true);
        (r.data || []).forEach(function (row) {
            var it = row.shop_items; if (!it) return;
            if (it.item_type === 'frame') out.frame = it;
            else if (it.item_type === 'badge') out.badges.push(it);
            else if (it.item_type === 'title') out.title = it;
        });
    } catch (e) {}
    return out;
}
/* 头像框 CSS（商城页与个人主页共用） */
var SHOP_FRAME_CSS = [
    '.avatar-frame{border-radius:50%;padding:3px;}',
    '.frame-gold{border:3px solid #ffd43b;box-shadow:0 0 14px rgba(255,212,59,.65);}',
    '.frame-cyber{border:3px solid #00e5ff;box-shadow:0 0 14px rgba(0,229,255,.6);}',
    '.frame-rainbow{border:3px solid transparent;background:linear-gradient(45deg,#ff5f5f,#ffb84d,#f9f871,#7bf59b,#5fb8ff,#c07bff,#ff7bd5) border-box;animation:frameSpin 3s linear infinite;background-size:300% 300%;}',
    '@keyframes frameSpin{0%{background-position:0% 50%;}50%{background-position:100% 50%;}100%{background-position:0% 50%;}}'
].join('\n');
function injectFrameCSS() {
    if (document.getElementById('shop-frame-css')) return;
    var st = document.createElement('style');
    st.id = 'shop-frame-css'; st.textContent = SHOP_FRAME_CSS;
    document.head.appendChild(st);
}
async function myPoints() {
    try {
        var me = await currentUser();
        if (!me) return 0;
        var r = await window.sb.from('profiles').select('points').eq('id', me.id).single();
        return (r.data && r.data.points) || 0;
    } catch (e) { return 0; }
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


/* ===== 全局加载蒙面 ===== */
function showLoading(text) {
    var ov = document.getElementById('mmc-loading');
    if (!ov) {
        ov = document.createElement('div');
        ov.id = 'mmc-loading';
        ov.innerHTML = '<div class="mmc-loading-box"><div class="mmc-spinner"></div><div class="mmc-loading-text"></div></div>' +
            '<style>#mmc-loading{position:fixed;inset:0;z-index:99999;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.55);backdrop-filter:blur(2px)}' +
            '.mmc-loading-box{display:flex;flex-direction:column;align-items:center;gap:14px;background:#1c1c24;border:1px solid #333;padding:28px 36px;border-radius:14px}' +
            '.mmc-spinner{width:38px;height:38px;border-radius:50%;border:4px solid #444;border-top-color:#ffcc00;animation:mmcspin 0.8s linear infinite}' +
            '@keyframes mmcspin{to{transform:rotate(360deg)}}' +
            '.mmc-loading-text{color:#eee;font-size:15px}</style>';
        document.body.appendChild(ov);
    }
    var t = ov.querySelector('.mmc-loading-text');
    if (t) t.textContent = text || '加载中…';
    ov.style.display = 'flex';
}
function hideLoading() {
    var ov = document.getElementById('mmc-loading');
    if (ov) ov.style.display = 'none';
}
/* 内部跳转自动蒙面 */
document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = a.getAttribute('href') || '';
    if (!href || href.charAt(0) === '#' || href.indexOf('javascript:') === 0) return;
    if (a.target === '_blank') return;
    if (/^https?:\/\//i.test(href) && href.indexOf(location.host) === -1) return;
    showLoading('跳转中…');
});
/* 带超时的 Promise，防请求 hanging */
function withTimeout(promise, ms, msg) {
    return Promise.race([
        promise,
        new Promise(function (_, reject) {
            setTimeout(function () { reject(new Error(msg || '请求超时，请检查网络后重试')); }, ms || 25000);
        })
    ]);
}

/* ===== 轻量 Markdown 渲染（先转义防 XSS，再解析常用语法） ===== */
function md(src) {
    var s = String(src == null ? '' : src);
    s = s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    var codeBlocks = [];
    s = s.replace(/```([\s\S]*?)```/g, function (m, c) {
        codeBlocks.push('<pre class="md-pre"><code>' + c.replace(/^\n+|\n+$/g, '') + '</code></pre>');
        return '\u0000' + (codeBlocks.length - 1) + '\u0000';
    });
    var codes = [];
    s = s.replace(/`([^`\n]+)`/g, function (m, c) {
        codes.push('<code class="md-code">' + c + '</code>');
        return '\u0001' + (codes.length - 1) + '\u0001';
    });
    s = s.replace(/^######\s?(.*)$/gm, '<h6 class="md-h">$1</h6>')
         .replace(/^#####\s?(.*)$/gm, '<h5 class="md-h">$1</h5>')
         .replace(/^####\s?(.*)$/gm, '<h4 class="md-h">$1</h4>')
         .replace(/^###\s?(.*)$/gm, '<h3 class="md-h">$1</h3>')
         .replace(/^##\s?(.*)$/gm, '<h2 class="md-h">$1</h2>')
         .replace(/^#\s?(.*)$/gm, '<h1 class="md-h">$1</h1>');
    s = s.replace(/^&gt;\s?(.*)$/gm, '<blockquote class="md-quote">$1</blockquote>');
    s = s.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
         .replace(/__([^_]+)__/g, '<b>$1</b>')
         .replace(/\*([^*\n]+)\*/g, '<i>$1</i>')
         .replace(/_([^_\n]+)_/g, '<i>$1</i>')
         .replace(/~~([^~]+)~~/g, '<del>$1</del>');
    s = s.replace(/!\[([^\]]*)\]\((https?:[^)\s]+)\)/g, '<img class="md-img" alt="$1" src="$2" loading="lazy">')
         .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a class="md-link" href="$2" target="_blank" rel="noopener">$1</a>');
    /* 列表：连续的 - / * / 数字行合并 */
    s = s.replace(/((?:^|\n)(?:\s*[-*]\s+[^\n]+\n?)+)/g, function (m) {
        var items = m.trim().split('\n').map(function (l) {
            return '<li>' + l.replace(/^\s*[-*]\s+/, '') + '</li>';
        }).join('');
        return '\n<ul class="md-ul">' + items + '</ul>\n';
    });
    s = s.replace(/((?:^|\n)(?:\s*\d+\.\s+[^\n]+\n?)+)/g, function (m) {
        var items = m.trim().split('\n').map(function (l) {
            return '<li>' + l.replace(/^\s*\d+\.\s+/, '') + '</li>';
        }).join('');
        return '\n<ol class="md-ol">' + items + '</ol>\n';
    });
    s = s.split('\n').map(function (l) {
        var t = l.trim();
        if (!t) return '';
        if (/^<(h\d|ul|ol|li|blockquote|pre|img)/.test(t)) return l;
        return '<p class="md-p">' + l + '</p>';
    }).join('\n');
    s = s.replace(/\u0000(\d+)\u0000/g, function (m, i) { return codeBlocks[+i]; })
         .replace(/\u0001(\d+)\u0001/g, function (m, i) { return codes[+i]; });
    return s;
}
/* Markdown 语法说明弹窗 */
function mdHelp() {
    var ov = document.getElementById('mmc-mdhelp');
    if (ov) { ov.style.display = 'flex'; return; }
    ov = document.createElement('div');
    ov.id = 'mmc-mdhelp';
    ov.innerHTML = '<div class="mmc-mdhelp-box"><h3>📝 Markdown 语法说明</h3>' +
        '<table class="mmc-mdhelp-tb">' +
        '<tr><td><code>**粗体**</code></td><td><b>粗体</b></td></tr>' +
        '<tr><td><code>*斜体*</code></td><td><i>斜体</i></td></tr>' +
        '<tr><td><code>~~删除线~~</code></td><td><del>删除线</del></td></tr>' +
        '<tr><td><code>`代码`</code></td><td><code class="md-code">代码</code></td></tr>' +
        '<tr><td><code>```<br>代码块<br>```</code></td><td>多行代码块</td></tr>' +
        '<tr><td><code># 标题</code></td><td>大标题（## 更小）</td></tr>' +
        '<tr><td><code>&gt; 引用</code></td><td>引用块</td></tr>' +
        '<tr><td><code>- 列表项</code></td><td>无序列表</td></tr>' +
        '<tr><td><code>1. 列表项</code></td><td>有序列表</td></tr>' +
        '<tr><td><code>[文字](https://…)</code></td><td>超链接</td></tr>' +
        '<tr><td><code>![说明](https://….png)</code></td><td>图片</td></tr>' +
        '</table><button class="btn btn-blue" id="mmc-mdhelp-close">知道了</button></div>' +
        '<style>#mmc-mdhelp{position:fixed;inset:0;z-index:99999;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.6)}' +
        '.mmc-mdhelp-box{background:#1c1c24;border:1px solid #444;border-radius:14px;padding:22px;max-width:420px;width:92%;max-height:80vh;overflow:auto}' +
        '.mmc-mdhelp-box h3{margin:0 0 12px}' +
        '.mmc-mdhelp-tb{width:100%;border-collapse:collapse;margin-bottom:14px;font-size:14px}' +
        '.mmc-mdhelp-tb td{border-bottom:1px solid #333;padding:7px 6px;vertical-align:top}' +
        '.mmc-mdhelp-tb code{background:#2a2a35;padding:2px 6px;border-radius:4px}</style>';
    document.body.appendChild(ov);
    document.getElementById('mmc-mdhelp-close').addEventListener('click', function () { ov.style.display = 'none'; });
    ov.addEventListener('click', function (e) { if (e.target === ov) ov.style.display = 'none'; });
}
/* 在 textarea 旁插入 “Markdown 说明” 小按钮，传 textarea 的 id */
function mdHelpBtn(textareaId) {
    return ' <a href="javascript:void(0)" onclick="mdHelp()" style="font-size:12px;color:#8ab4ff">📝 Markdown 说明</a>';
}

/* Markdown 输出基础样式（注入一次） */
(function () {
    if (document.getElementById('mmc-md-style')) return;
    var st = document.createElement('style');
    st.id = 'mmc-md-style';
    st.textContent = '.md-p{margin:.5em 0;line-height:1.7;word-break:break-word}' +
        '.md-h{margin:.7em 0 .4em;line-height:1.4}' +
        '.md-quote{border-left:3px solid #4d7cfe;padding:6px 12px;margin:.6em 0;background:rgba(77,124,254,.08);border-radius:0 8px 8px 0}' +
        '.md-code{background:#2a2a35;padding:2px 6px;border-radius:4px;font-family:monospace;font-size:.92em}' +
        '.md-pre{background:#16161d;border:1px solid #333;border-radius:8px;padding:12px;overflow-x:auto;margin:.6em 0}' +
        '.md-pre code{font-family:monospace;font-size:.9em;line-height:1.6}' +
        '.md-ul,.md-ol{margin:.5em 0;padding-left:1.6em;line-height:1.7}' +
        '.md-img{max-width:100%;border-radius:8px;margin:.4em 0}' +
        '.md-link{color:#8ab4ff}';
    document.head.appendChild(st);
})();

/* ===== @提及通知 ===== */
/* 提取文本中的 @用户名 */
function parseMentions(text) {
    var names = [];
    var re = /@([\u4e00-\u9fa5\w-]+)/g, m;
    while ((m = re.exec(text)) !== null) {
        if (names.indexOf(m[1]) < 0) names.push(m[1]);
    }
    return names;
}
/* 提交成功后调用：按用户名批量查用户，给被@者发通知（跳过自己，SQL 亦有 guard） */
async function sendMentions(text, actorId, refId, refType) {
    var names = parseMentions(text);
    if (!names.length || !actorId) return;
    try {
        var r = await sb.from('profiles').select('id,username').in('username', names);
        var users = r.data || [];
        for (var i = 0; i < users.length; i++) {
            var u = users[i];
            if (u.id === actorId) continue;
            try {
                await sb.rpc('send_mention', {
                    p_user_id: u.id,
                    p_actor_id: actorId,
                    p_content: String(text).slice(0, 200),
                    p_ref_id: refId || null,
                    p_ref_type: refType || null
                });
            } catch (e) { /* 单个失败不影响其他 */ }
        }
    } catch (e) {}
}
