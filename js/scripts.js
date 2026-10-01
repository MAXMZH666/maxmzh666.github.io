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

    /* 滚动显现动画 */
    var revealEls = document.querySelectorAll('.reveal');
    if ('IntersectionObserver' in window && revealEls.length) {
        var io = new IntersectionObserver(function (entries) {
            entries.forEach(function (en) {
                if (en.isIntersecting) {
                    en.target.classList.add('visible');
                    io.unobserve(en.target);
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
