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

    /* 联系表单：用 mailto 打开用户邮箱发送 */
    var cform = document.getElementById('contactForm');
    if (cform) {
        cform.addEventListener('submit', function (e) {
            e.preventDefault();
            var name = document.getElementById('cf-name').value.trim();
            var email = document.getElementById('cf-email').value.trim();
            var msg = document.getElementById('cf-message').value.trim();
            var subject = encodeURIComponent('来自个人网站的留言 - ' + name);
            var body = encodeURIComponent('姓名：' + name + '\n邮箱：' + email + '\n\n' + msg);
            location.href = 'mailto:2926357395@qq.com?subject=' + subject + '&body=' + body;
        });
    }
})();
