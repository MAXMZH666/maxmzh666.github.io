/* MAXMZH 个人主页 · 通用脚本 */
(function () {
    'use strict';

    /* 页脚年份自动更新 */
    document.querySelectorAll('[data-year]').forEach(function (el) {
        el.textContent = new Date().getFullYear();
    });

    /* 移动端导航开关 */
    var toggle = document.querySelector('.nav-toggle');
    var links = document.querySelector('.nav-links');
    if (toggle && links) {
        toggle.addEventListener('click', function () {
            var open = links.classList.toggle('open');
            toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        });
        links.addEventListener('click', function (e) {
            if (e.target.tagName === 'A') links.classList.remove('open');
        });
    }

    /* 当前页面导航高亮 */
    try {
        var page = (location.pathname.split('/').pop() || 'index.html').toLowerCase();
        document.querySelectorAll('.nav-links a').forEach(function (a) {
            var href = (a.getAttribute('href') || '').toLowerCase();
            if (href === page || (page === '' && href === 'index.html')) {
                a.classList.add('active');
            }
        });
    } catch (e) { /* 忽略 */ }

    /* 滚动显现动画（入场 + 可选出场） */
    var revealEls = document.querySelectorAll('.reveal');
    if ('IntersectionObserver' in window && revealEls.length) {
        var io = new IntersectionObserver(function (entries) {
            entries.forEach(function (en) {
                if (en.isIntersecting) {
                    en.target.classList.add('visible');
                    /* 只有带 reveal-out 的元素才播出场动画，其余一次入场后不再观察 */
                    if (!en.target.classList.contains('reveal-out')) {
                        io.unobserve(en.target);
                    }
                } else if (en.target.classList.contains('reveal-out')) {
                    en.target.classList.remove('visible');
                }
            });
        }, { threshold: 0.12 });
        revealEls.forEach(function (el) { io.observe(el); });
    } else {
        revealEls.forEach(function (el) { el.classList.add('visible'); });
    }

    /* 联系表单：通过 FormSubmit 真实发送邮件到站长邮箱 */
    var cform = document.getElementById('contactForm');
    if (cform) {
        cform.addEventListener('submit', function (e) {
            e.preventDefault();
            var note = document.getElementById('form-note');
            var btn = cform.querySelector('button[type="submit"]');
            var name = document.getElementById('cf-name').value.trim();
            var email = document.getElementById('cf-email').value.trim();
            var msg = document.getElementById('cf-message').value.trim();
            if (note) { note.textContent = '发送中…'; note.className = 'form-note sending'; }
            if (btn) btn.disabled = true;
            fetch('https://formsubmit.co/ajax/2926357395@qq.com', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
                body: JSON.stringify({
                    name: name,
                    email: email,
                    message: msg,
                    _subject: '网站联系表单：' + name,
                    _template: 'table'
                })
            }).then(function (r) { return r.json(); }).then(function () {
                if (note) { note.textContent = '发送成功！我会尽快回复你。'; note.className = 'form-note ok'; }
                cform.reset();
            }).catch(function () {
                if (note) { note.textContent = '发送失败，请稍后重试，或直接发邮件到 2926357395@qq.com'; note.className = 'form-note err'; }
            }).finally(function () {
                if (btn) btn.disabled = false;
            });
        });
    }
})();

/* ---------- 深色 / 浅色模式 ---------- */
(function () {
    var KEY = 'maxmzh-theme';
    var btn = document.getElementById('theme-toggle');

    function current() {
        return document.documentElement.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
    }
    function paint() {
        if (btn) btn.textContent = current() === 'light' ? '🌙' : '☀️';
    }
    function syncGiscus() {
        var frame = document.querySelector('iframe.giscus-frame');
        if (!frame) return;
        try {
            frame.contentWindow.postMessage({ giscus: { setConfig: { theme: current() } } }, 'https://giscus.app');
        } catch (e) {}
    }
    if (btn) {
        btn.addEventListener('click', function () {
            var next = current() === 'light' ? 'dark' : 'light';
            if (next === 'light') document.documentElement.setAttribute('data-theme', 'light');
            else document.documentElement.removeAttribute('data-theme');
            try { localStorage.setItem(KEY, next); } catch (e) {}
            paint();
            syncGiscus();
        });
    }
    paint();
    // 论坛页：giscus 加载完成后同步一次主题
    if (document.querySelector('script[src*="giscus"]')) {
        var tries = 0;
        var timer = setInterval(function () {
            tries++;
            var frame = document.querySelector('iframe.giscus-frame');
            if (frame || tries > 20) {
                clearInterval(timer);
                if (frame && current() === 'light') syncGiscus();
            }
        }, 500);
    }
})();

/* ---------- 作品集搜索与筛选 ---------- */
(function () {
    var input = document.getElementById('work-search');
    var grid = document.getElementById('work-grid');
    if (!input || !grid) return;
    var chips = document.querySelectorAll('.filter-chip');
    var empty = document.getElementById('work-empty');
    var count = document.getElementById('work-count');
    var cards = Array.prototype.slice.call(grid.querySelectorAll('.card'));
    var cat = 'all';

    function apply() {
        var q = input.value.trim().toLowerCase();
        var shown = 0;
        cards.forEach(function (card) {
            var okCat = cat === 'all' || card.getAttribute('data-category') === cat;
            var okQ = !q || (card.getAttribute('data-search') || '').toLowerCase().indexOf(q) !== -1;
            var show = okCat && okQ;
            card.style.display = show ? '' : 'none';
            if (show) shown++;
        });
        if (empty) empty.style.display = shown ? 'none' : 'block';
        if (count) count.textContent = '共 ' + shown + ' 个作品';
    }
    input.addEventListener('input', apply);
    chips.forEach(function (chip) {
        chip.addEventListener('click', function () {
            chips.forEach(function (c) { c.classList.remove('active'); });
            chip.classList.add('active');
            cat = chip.getAttribute('data-filter');
            apply();
        });
    });
    apply();
})();

/* ---------- 回到顶部 ---------- */
(function () {
    var btn = document.createElement('button');
    btn.id = 'back-top';
    btn.setAttribute('aria-label', '回到顶部');
    btn.textContent = '↑';
    document.body.appendChild(btn);
    function onScroll() {
        btn.classList.toggle('show', window.scrollY > 400);
    }
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    btn.addEventListener('click', function () {
        window.scrollTo({ top: 0, behavior: 'smooth' });
    });
})();

/* 页面跳转加载过渡 */
(function () {
    var overlay = document.createElement('div');
    overlay.id = 'page-loader';
    overlay.innerHTML = '<div class="loader-spinner"></div><p>加载中…</p>';
    overlay.style.display = 'none';
    document.body.appendChild(overlay);
    var show = function () { overlay.style.display = 'flex'; };
    var hide = function () { overlay.style.display = 'none'; };
    document.addEventListener('click', function (e) {
        var a = e.target.closest ? e.target.closest('a[href]') : null;
        if (!a) return;
        var href = a.getAttribute('href');
        if (!href || href.charAt(0) === '#' || a.target === '_blank' ||
            a.hasAttribute('download') || a.dataset.noTransition !== undefined) return;
        var url;
        try { url = new URL(href, location.href); } catch (err) { return; }
        if (url.origin !== location.origin) return;
        if (url.pathname === location.pathname && url.search === location.search) return;
        show();
        /* 兜底：8 秒后自动隐藏（防止 bfcache 等异常） */
        setTimeout(hide, 8000);
    });
    window.addEventListener('pageshow', hide);
    if (document.readyState === 'complete') hide(); else window.addEventListener('load', hide);
})();
