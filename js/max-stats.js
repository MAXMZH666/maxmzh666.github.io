/* MAX 自建访问统计：回填页面里已有的不蒜子计数 span（后端在自家服务器，不再依赖第三方） */
(function () {
    'use strict';
    var elSite = document.getElementById('busuanzi_value_site_pv');
    var elPage = document.getElementById('busuanzi_value_page_pv');
    var elUv = document.getElementById('busuanzi_value_site_uv');
    if (!elSite && !elPage && !elUv) return;
    fetch('/stats/hit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: location.pathname })
    }).then(function (r) { return r.json(); }).then(function (d) {
        if (elSite && typeof d.site_pv === 'number') elSite.textContent = d.site_pv;
        if (elPage && typeof d.page_pv === 'number') elPage.textContent = d.page_pv;
        if (elUv && typeof d.site_uv === 'number') elUv.textContent = d.site_uv;
    }).catch(function () { /* 统计失败不影响页面 */ });
})();
