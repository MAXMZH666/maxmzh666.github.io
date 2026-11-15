/* MAX 全站语言切换（简体中文 / English）
 * 机制：按中文原文查字典替换文本节点；范围 = 页眉/子页眉/页脚 + 带 data-i18n 的元素。
 * 用户发布的内容（作品、帖子、评论）不翻译。选择存 localStorage(maxmzh-lang)，切换时刷新页面生效。
 */
(function () {
    var KEY = 'maxmzh-lang';
    var DICT = {
        '主页': 'Home', '个人简介': 'About', '博客': 'Blog', '社区': 'Community', '联系方式': 'Contact',
        'MAX论坛': 'MAX Forum', '应用商店': 'App Store', '图床': 'Image Host', 'MAX工作室': 'MAX Studio',
        'MAX编程社区': 'MAX Coding Community', 'MAX 应用商店': 'MAX App Store', 'MAX 账号': 'MAX Account',
        '首页': 'Home', '🔍 发现': '🔍 Discover', '发现': 'Discover', '💬 论坛': '💬 Forum', '论坛': 'Forum',
        '🏢 工作室': '🏢 Studios', '工作室': 'Studios', '🎁 任务商城': '🎁 Quests & Shop', '任务商城': 'Quests & Shop',
        '🏁 赛事': '🏁 Contests', '赛事': 'Contests', '⚖️ 共建': '⚖️ Co-build', '共建': 'Co-build',
        '🚀 发布': '🚀 Publish', '发布': 'Publish', '＋ 发布作品': '＋ Publish Work', '发布作品': 'Publish Work',
        '逛逛作品': 'Browse Works', '📢 社区公告': '📢 Announcements', '社区公告': 'Announcements',
        '🔥 热门作品': '🔥 Trending Works', '热门作品': 'Trending Works', '全部作品 →': 'All Works →',
        '🏁 热门赛事': '🏁 Hot Contests', '全部赛事 →': 'All Contests →', '加载中…': 'Loading…', '加载中...': 'Loading...',
        '🆕 最新发布': '🆕 Latest', '最新发布': 'Latest',
        '登录': 'Log in', '注册': 'Sign up', '退出': 'Log out', '退出登录': 'Log out',
        '个人主页': 'My Profile', '个人设置': 'Settings', '账号设置': 'Account Settings',
        '我的私信': 'My Messages', '私信': 'Messages', '我的收藏': 'My Favorites', '收藏': 'Favorites',
        '数据看板': 'Dashboard', '我的数据': 'My Stats', '通知': 'Notifications', '动态': 'Feed',
        '搜索': 'Search', '站长后台': 'Admin', '后台管理': 'Admin', '管理后台': 'Admin',
        '本站总访问量': 'Total visits', '本页访问': 'Page views', '统计中…': 'Counting…', '次': 'times',
        '保存': 'Save', '保存修改': 'Save Changes', '取消': 'Cancel', '确定': 'OK', '删除': 'Delete',
        '编辑': 'Edit', '返回': 'Back', '关闭': 'Close', '提交': 'Submit', '确认': 'Confirm',
        '邮箱': 'Email', '密码': 'Password', '原密码': 'Current Password', '新密码（至少 6 位）': 'New Password (min. 6 chars)',
        '确认新密码': 'Confirm New Password', '新邮箱': 'New Email', '验证码': 'Code',
        '修改密码': 'Change Password', '修改邮箱': 'Change Email', '个人设置': 'Settings',
        '⚙️ 个人设置': '⚙️ Settings', '🔐 修改密码': '🔐 Change Password', '📧 修改邮箱': '📧 Change Email',
        '🚫 屏蔽列表': '🚫 Block List', '🎛️ 个人喜好': '🎛️ Preferences',
        '在线编辑器自动保存间隔': 'Editor Autosave Interval', '发布作品时的默认分类': 'Default Category for New Works',
        '界面语言': 'Language', '主题模式': 'Theme', '暗色': 'Dark', '亮色': 'Light',
        '通知偏好': 'Notification Preferences', '界面偏好': 'Appearance',
        '被点赞时通知我': 'Notify me on likes', '被评论时通知我': 'Notify me on comments',
        '被关注时通知我': 'Notify me on follows', '论坛被回复时通知我': 'Notify me on forum replies',
        '收到私信时通知我': 'Notify me on messages',
        '我的账号状态': 'My Account', 'MAX 账号能用在哪': 'Where MAX Account Works',
        '注册与登录方式': 'Sign-up & Login', '⚠️ 账号安全提醒': '⚠️ Account Safety',
        '退出所有设备': 'Log out Everywhere', '导出我的数据': 'Export My Data',
        '账号信息': 'Account Info', '注册时间': 'Registered', '用户 ID': 'User ID',
        '打开社区': 'Open Community', '打开论坛': 'Open Forum', '打开编辑器': 'Open Editor',
        '打开商店': 'Open Store', '打开图床': 'Open Image Host', '去登录页': 'Go to Login',
        '一个账号，走遍 MAX 的全部产品：在社区发作品、在论坛讨论、在编辑器里存草稿，都认这一个账号，不用每个地方重新注册。':
            'One account for every MAX product: post works in the community, discuss in the forum, save drafts in the editor — no need to register again anywhere.',
        '← MAX 应用商店': '← MAX App Store', '← 返回': '← Back',
        '全部': 'All', '游戏': 'Games', '工具': 'Tools', '学习': 'Study', '其他': 'Other',
        '关注': 'Follow', '已关注': 'Following', '粉丝': 'Followers', '获赞': 'Likes',
        '评论': 'Comments', '点赞': 'Like', '回复': 'Reply', '举报': 'Report', '分享': 'Share',
        '下载': 'Download', '试玩': 'Play', '查看': 'View', '详情': 'Details'
    };

    function getLang() {
        try { return localStorage.getItem(KEY) === 'en' ? 'en' : 'zh'; } catch (e) { return 'zh'; }
    }
    function translateTextNode(node) {
        var raw = node.nodeValue;
        if (!raw) return;
        var key = raw.trim();
        if (!key || !DICT[key]) return;
        node.nodeValue = raw.replace(key, DICT[key]);
    }
    function walk(root) {
        if (!root) return;
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (n) {
                if (!n.nodeValue || !n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
                var p = n.parentElement;
                if (!p || p.id === 'max-lang-select' || p.closest('script, style, #max-lang-select')) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }
        });
        var nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);
        nodes.forEach(translateTextNode);
        root.querySelectorAll('[data-i18n]').forEach(function (el) {
            var k = el.getAttribute('data-i18n');
            if (k && DICT[k]) el.textContent = DICT[k];
        });
        root.querySelectorAll('[data-i18n-ph]').forEach(function (el) {
            var k = el.getAttribute('data-i18n-ph');
            if (k && DICT[k]) el.setAttribute('placeholder', DICT[k]);
        });
    }
    function apply() {
        if (getLang() !== 'en') return;
        document.documentElement.setAttribute('lang', 'en');
        document.querySelectorAll('header, footer, .sub-header').forEach(walk);
        document.querySelectorAll('[data-i18n], [data-i18n-ph]').forEach(function (el) {
            var k = el.getAttribute('data-i18n');
            if (k && DICT[k]) el.textContent = DICT[k];
            var p = el.getAttribute('data-i18n-ph');
            if (p && DICT[p]) el.setAttribute('placeholder', DICT[p]);
        });
    }
    function injectStyle() {
        if (document.getElementById('max-lang-style')) return;
        var st = document.createElement('style');
        st.id = 'max-lang-style';
        st.textContent =
            '#max-lang-select{appearance:none;-webkit-appearance:none;background:rgba(128,140,180,.14);color:inherit;' +
            'border:1px solid rgba(128,140,180,.35);border-radius:999px;padding:5px 22px 5px 10px;font-size:13px;cursor:pointer;' +
            'background-image:url("data:image/svg+xml;charset=utf8,%3Csvg xmlns=\'http://www.w3.org/2000/svg\' width=\'8\' height=\'6\'%3E%3Cpath d=\'M0 0l4 6 4-6z\' fill=\'%23888\'/%3E%3C/svg%3E");' +
            'background-repeat:no-repeat;background-position:right 8px center;}' +
            '#max-lang-select:focus{outline:none;border-color:#4d7cfe;}' +
            '#max-lang-float{position:fixed;right:14px;bottom:150px;z-index:9998;box-shadow:0 6px 20px rgba(0,0,0,.25);}';
        document.head.appendChild(st);
    }
    function injectSelector() {
        if (document.getElementById('max-lang-select')) return;
        injectStyle();
        var sel = document.createElement('select');
        sel.id = 'max-lang-select';
        sel.setAttribute('aria-label', 'Language');
        sel.innerHTML = '<option value="zh">🌐 简体中文</option><option value="en">🌐 English</option>';
        sel.value = getLang();
        sel.addEventListener('change', function () { window.MaxI18n.set(sel.value); });
        var anchor = document.getElementById('theme-toggle');
        if (anchor && anchor.parentElement) {
            anchor.parentElement.insertBefore(sel, anchor);
            sel.style.marginRight = '8px';
            return;
        }
        var header = document.querySelector('header.site-header, header');
        if (header) {
            header.appendChild(sel);
            sel.style.marginLeft = '10px';
            return;
        }
        sel.id = 'max-lang-select';
        sel.classList.add('max-lang-float');
        sel.style.position = 'fixed';
        document.body.appendChild(sel);
    }

    window.MaxI18n = {
        get: getLang,
        set: function (lang) {
            try { localStorage.setItem(KEY, lang === 'en' ? 'en' : 'zh'); } catch (e) {}
            location.reload();
        },
        dict: DICT
    };

    function init() {
        injectSelector();
        apply();
        if (getLang() === 'en' && document.body) {
            var pending = null;
            var obs = new MutationObserver(function () {
                if (pending) return;
                pending = setTimeout(function () { pending = null; apply(); }, 350);
            });
            obs.observe(document.body, { childList: true, subtree: true });
        }
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
})();
