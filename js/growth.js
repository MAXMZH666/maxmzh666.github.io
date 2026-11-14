/* 成长体系共享模块：等级计算 / 经验发放 / 装扮查询 / 每日签到（论坛与社区共用）
   经验规则：签到 +5、发帖 +10、回帖 +3、回帖被点赞 +2、发布作品 +15
   积分规则与任务商城签到一致：签到 +5，连续 7 天额外 +10、30 天额外 +30 */
(function () {
    if (window.Growth) return;
    var THRESHOLDS = [0, 30, 90, 200, 400, 700, 1100, 1700, 2500, 3600];
    function levelOf(exp) {
        exp = Math.max(0, exp | 0);
        var lv = 1;
        for (var i = 0; i < THRESHOLDS.length; i++) { if (exp >= THRESHOLDS[i]) lv = i + 1; }
        var cur = THRESHOLDS[lv - 1];
        var next = lv < THRESHOLDS.length ? THRESHOLDS[lv] : null;
        return { lv: lv, exp: exp, cur: cur, next: next, pct: next ? Math.min(100, Math.floor((exp - cur) / (next - cur) * 100)) : 100 };
    }
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function badge(exp) {
        var l = levelOf(exp);
        return '<span class="lv-badge" title="经验值 ' + l.exp + '">Lv.' + l.lv + '</span>';
    }
    var CSS = [
        '.lv-badge{display:inline-block;font-size:.68rem;font-weight:700;line-height:1.5;color:#fff;background:linear-gradient(135deg,#4d7cfe,#6d5cff);border-radius:8px;padding:0 6px;margin-left:6px;vertical-align:middle;white-space:nowrap}',
        '.title-pill{font-size:.72rem;color:#b8860b;border:1px solid #ffd43b;background:rgba(255,212,59,.12);border-radius:12px;padding:1px 8px;margin-right:6px;vertical-align:middle;white-space:nowrap}',
        '.avatar-frame{border-radius:50%;padding:3px;box-sizing:content-box}',
        '.frame-gold{border:3px solid #ffd43b;box-shadow:0 0 14px rgba(255,212,59,.65)}',
        '.frame-cyber{border:3px solid #00e5ff;box-shadow:0 0 14px rgba(0,229,255,.6)}',
        '.frame-rainbow{border:3px solid transparent;background:linear-gradient(45deg,#ff5f5f,#ffb84d,#f9f871,#7bf59b,#5fb8ff,#c07bff,#ff7bd5) border-box;animation:frameSpin 3s linear infinite;background-size:300% 300%}',
        '.frame-legend{border:3px solid #ff922b;box-shadow:0 0 18px rgba(255,146,43,.8),0 0 4px rgba(255,146,43,.9)}',
        '.frame-diamond{border:3px solid #a5f3fc;box-shadow:0 0 20px rgba(165,243,252,.85),0 0 6px rgba(165,243,252,1);animation:frameDiamond 2.4s ease-in-out infinite}',
        '@keyframes frameDiamond{0%,100%{box-shadow:0 0 12px rgba(165,243,252,.5)}50%{box-shadow:0 0 26px rgba(165,243,252,1)}}',
        '@keyframes frameSpin{0%{background-position:0% 50%}50%{background-position:100% 50%}100%{background-position:0% 50%}}',
        '.exp-progress{height:8px;border-radius:99px;background:rgba(127,127,127,.25);overflow:hidden;min-width:140px}',
        '.exp-progress>i{display:block;height:100%;border-radius:99px;background:linear-gradient(90deg,#4d7cfe,#6d5cff)}'
    ].join('\n');
    function ensureCss() {
        if (document.getElementById('growth-css')) return;
        var st = document.createElement('style');
        st.id = 'growth-css'; st.textContent = CSS;
        document.head.appendChild(st);
    }
    /* 发经验：ref 非空时按 (user_id, ref) 防重复；读-改-写 profiles.exp 后记 exp_log */
    async function awardExp(sb, uid, delta, reason, ref) {
        try {
            if (!sb || !uid || !delta) return false;
            if (ref) {
                var q = await sb.from('exp_log').select('id').eq('user_id', uid).eq('ref', ref).limit(1);
                if (q.data && q.data.length) return false;
            }
            var pr = await sb.from('profiles').select('exp').eq('id', uid).single();
            var cur = (pr.data && pr.data.exp) || 0;
            var ur = await sb.from('profiles').update({ exp: cur + delta }).eq('id', uid);
            if (ur.error) return false;
            await sb.from('exp_log').insert({ user_id: uid, delta: delta, reason: reason || '经验变动', ref: ref || null });
            return true;
        } catch (e) { return false; }
    }
    /* 批量查已装备装扮：返回 { uid: {frame: shop_items行|null, title: shop_items行|null} } */
    async function decorOf(sb, userIds) {
        var out = {};
        try {
            if (!userIds || !userIds.length) return out;
            var r = await sb.from('user_items').select('user_id,shop_items(item_type,item_data,name)')
                .in('user_id', userIds).eq('is_equipped', true);
            (r.data || []).forEach(function (row) {
                var it = row.shop_items; if (!it) return;
                var m = out[row.user_id] || (out[row.user_id] = { frame: null, title: null });
                if (it.item_type === 'frame') m.frame = it;
                else if (it.item_type === 'title') m.title = it;
            });
        } catch (e) {}
        return out;
    }
    /* ===== 每日签到（与 community-shop 任务页同一套规则） ===== */
    function fmtDay(d) {
        return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
    }
    async function calcStreak(sb, uid) {
        try {
            var r = await sb.from('checkins').select('check_date').eq('user_id', uid)
                .order('check_date', { ascending: false }).limit(40);
            var dates = (r.data || []).map(function (x) { return x.check_date; });
            if (!dates.length) return 0;
            var today = new Date();
            var startOk = dates[0] === fmtDay(today) || dates[0] === fmtDay(new Date(today.getTime() - 86400000));
            if (!startOk) return 0;
            var streak = 0;
            var cursor = dates[0] === fmtDay(today) ? today : new Date(today.getTime() - 86400000);
            for (var i = 0; i < dates.length; i++) {
                if (dates[i] === fmtDay(cursor)) { streak++; cursor = new Date(cursor.getTime() - 86400000); }
                else break;
            }
            return streak;
        } catch (e) { return 0; }
    }
    async function addPoints(sb, uid, amount) {
        try {
            var pr = await sb.from('profiles').select('points').eq('id', uid).single();
            var cur = (pr.data && pr.data.points) || 0;
            var r = await sb.from('profiles').update({ points: cur + amount }).eq('id', uid);
            return !r.error;
        } catch (e) { return false; }
    }
    async function checkinState(sb, uid) {
        var todayStr = fmtDay(new Date());
        var cr = await sb.from('checkins').select('check_date').eq('user_id', uid).eq('check_date', todayStr).limit(1);
        var checked = !!(cr.data && cr.data.length);
        var streak = await calcStreak(sb, uid);
        return { checked: checked, streak: streak, todayStr: todayStr };
    }
    /* 执行签到：插入记录（主键防重复）→ 发积分（含里程碑）→ 发经验 +5 */
    async function doCheckin(sb, me) {
        var todayStr = fmtDay(new Date());
        var ir = await sb.from('checkins').insert({ user_id: me.id, check_date: todayStr, points_awarded: 5 });
        if (ir.error) throw ir.error;
        var newStreak = await calcStreak(sb, me.id);
        var bonus = 5;
        var msg = '签到成功 +5 积分 +5 经验';
        if (newStreak === 7) { bonus += 10; msg += '，连续 7 天额外 +10 积分！'; }
        else if (newStreak === 30) { bonus += 30; msg += '，连续 30 天额外 +30 积分！'; }
        else if (newStreak > 1) { msg += '，已连续 ' + newStreak + ' 天'; }
        var ok = await addPoints(sb, me.id, bonus);
        if (!ok) throw new Error('积分更新失败');
        await awardExp(sb, me.id, 5, '每日签到', 'checkin:' + todayStr);
        return { streak: newStreak, msg: msg };
    }
    window.Growth = {
        THRESHOLDS: THRESHOLDS, levelOf: levelOf, badge: badge, esc: esc,
        ensureCss: ensureCss, awardExp: awardExp, decorOf: decorOf,
        checkinState: checkinState, doCheckin: doCheckin, fmtDay: fmtDay
    };
})();
