/* ============================================================
 * MAX 账号（联合登录）—— maxmzh.com 全部网页产品共用 MAX社区账号
 * ------------------------------------------------------------
 * 原理：所有产品同域（maxmzh.com），共用同一个 Supabase 项目的
 * 登录态（localStorage 同源共享）。在社区登录一次，其它产品打开
 * 即已登录；未登录时点按钮跳到社区登录页，登录后自动跳回本页。
 *
 * 新产品接入（两步）：
 *   1) 页面里加一个容器：<div data-max-account></div>
 *      （或 data-max-account="float" 悬浮在右上角，适合没有顶栏的页面）
 *   2) 引入本文件：<script src="/js/max-account.js"></script>
 * 程序化用法：
 *   MaxAccount.ready().then(function (acc) { acc && acc.profile.username })
 *   acc = { user, profile } 或 null（未登录）
 * ============================================================ */
(function () {
    'use strict';
    var SUPABASE_URL = 'https://xkvpzxxtcnocofnsezpy.supabase.co';
    var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhrdnB6eHh0Y25vY29mbnNlenB5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5MTY4MzQsImV4cCI6MjEwNjQ5MjgzNH0.zTpvyEsutA9hV_UIg36g5owBRnxdHaI-sy_fLUsu6ec';
    var clientPromise = null;

    function getClient() {
        if (window.sb) return Promise.resolve(window.sb);
        if (clientPromise) return clientPromise;
        clientPromise = new Promise(function (resolve, reject) {
            function make() {
                try { resolve(window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)); }
                catch (e) { reject(e); }
            }
            if (window.supabase) return make();
            var s = document.createElement('script');
            s.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
            s.onload = make;
            s.onerror = reject;
            document.head.appendChild(s);
        });
        return clientPromise;
    }

    var cache = null; /* {user, profile} | null */
    var cacheDone = false;
    var waiters = [];

    function fetchAccount() {
        return getClient().then(function (sb) {
            return sb.auth.getSession().then(function (res) {
                var session = res && res.data && res.data.session;
                if (!session || !session.user) return null;
                var user = session.user;
                return sb.from('profiles').select('username, avatar_url').eq('id', user.id).single()
                    .then(function (r) { return { user: user, profile: (r && r.data) || null }; })
                    .catch(function () { return { user: user, profile: null }; });
            });
        }).catch(function () { return null; });
    }

    function ready() {
        return new Promise(function (resolve) {
            if (cacheDone) return resolve(cache);
            waiters.push(resolve);
            if (waiters.length === 1) {
                fetchAccount().then(function (acc) {
                    cache = acc; cacheDone = true;
                    var ws = waiters.splice(0);
                    ws.forEach(function (w) { w(cache); });
                    renderAll();
                });
            }
        });
    }

    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }

    var CSS = [
        '.maxacc{display:inline-flex;align-items:center;font-family:inherit}',
        '.maxacc-btn{display:inline-flex;align-items:center;gap:6px;background:linear-gradient(135deg,#4d7cfe,#6d5cff);color:#fff !important;border:none;border-radius:999px;padding:7px 14px;font-size:13px;font-weight:600;cursor:pointer;text-decoration:none !important;box-shadow:0 2px 10px rgba(77,124,254,.35)}',
        '.maxacc-btn:hover{filter:brightness(1.08)}',
        '.maxacc-chip{position:relative;display:inline-flex;align-items:center;gap:8px;cursor:pointer}',
        '.maxacc-ava{width:30px;height:30px;border-radius:50%;background:linear-gradient(135deg,#4d7cfe,#6d5cff);color:#fff;display:inline-flex;align-items:center;justify-content:center;font-size:14px;font-weight:700;overflow:hidden;flex:none}',
        '.maxacc-ava img{width:100%;height:100%;object-fit:cover}',
        '.maxacc-name{font-size:14px;font-weight:600;color:#e8ecf8;max-width:120px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
        '.maxacc-menu{position:absolute;top:calc(100% + 8px);right:0;background:#171c2e;border:1px solid rgba(255,255,255,.12);border-radius:12px;min-width:168px;padding:6px;display:none;z-index:99999;box-shadow:0 12px 32px rgba(0,0,0,.45)}',
        '.maxacc-menu.open{display:block}',
        '.maxacc-menu a,.maxacc-menu button{display:flex;width:100%;box-sizing:border-box;padding:9px 12px;border-radius:8px;color:#e8ecf8 !important;font-size:13px;text-decoration:none !important;background:none;border:none;cursor:pointer;text-align:left;font-family:inherit}',
        '.maxacc-menu a:hover,.maxacc-menu button:hover{background:rgba(77,124,254,.18)}',
        '.maxacc-float{position:fixed;top:14px;right:14px;z-index:99998;background:rgba(15,19,34,.82);backdrop-filter:blur(8px);border:1px solid rgba(255,255,255,.12);border-radius:999px;padding:5px 10px 5px 6px}'
    ].join('\n');

    var styleDone = false;
    function ensureStyle() {
        if (styleDone) return;
        styleDone = true;
        var st = document.createElement('style');
        st.textContent = CSS;
        document.head.appendChild(st);
    }

    function loginUrl() {
        return '/community-auth.html?next=' + encodeURIComponent(location.href);
    }

    function renderInto(el) {
        ensureStyle();
        var floatMode = el.getAttribute('data-max-account') === 'float';
        if (floatMode) el.classList.add('maxacc-float');
        el.classList.add('maxacc');
        if (!cacheDone) {
            el.innerHTML = '<span style="opacity:.55;font-size:13px;color:#aab">…</span>';
            return;
        }
        if (!cache) {
            el.innerHTML = '<a class="maxacc-btn" href="' + loginUrl() + '">使用 MAX 账号登录</a>';
            return;
        }
        var p = cache.profile || {};
        var name = p.username || (cache.user.email || 'MAX 用户').split('@')[0];
        var ava = p.avatar_url
            ? '<span class="maxacc-ava"><img src="' + esc(p.avatar_url) + '" alt=""></span>'
            : '<span class="maxacc-ava">' + esc(name.slice(0, 1).toUpperCase()) + '</span>';
        el.innerHTML =
            '<span class="maxacc-chip" tabindex="0">' + ava +
            '<span class="maxacc-name">' + esc(name) + '</span>' +
            '<span class="maxacc-menu">' +
            '<a href="/community-user.html?username=' + encodeURIComponent(name) + '">👤 我的社区主页</a>' +
            '<a href="/community.html">🌐 MAX社区</a>' +
            '<button type="button" data-maxacc-logout>🚪 退出登录</button>' +
            '</span></span>';
        var chip = el.querySelector('.maxacc-chip');
        var menu = el.querySelector('.maxacc-menu');
        chip.addEventListener('click', function (e) {
            if (e.target.closest('[data-maxacc-logout]')) return;
            menu.classList.toggle('open');
            e.stopPropagation();
        });
        document.addEventListener('click', function () { menu.classList.remove('open'); });
        el.querySelector('[data-maxacc-logout]').addEventListener('click', function () {
            getClient().then(function (sb) { return sb.auth.signOut(); })
                .then(function () { location.reload(); })
                .catch(function () { location.reload(); });
        });
    }

    function renderAll() {
        document.querySelectorAll('[data-max-account]').forEach(renderInto);
    }

    window.MaxAccount = { ready: ready, loginUrl: loginUrl };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () { renderAll(); ready(); });
    } else {
        renderAll(); ready();
    }
})();
