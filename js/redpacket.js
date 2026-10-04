/* ===== 🧧 积分红包通用模块 =====
 * 上下文：comment（评论区）、dm（私聊）、studio（工作室讨论室）、group（群聊）
 * 用法：
 *   redPacketButton(contextType, contextId)  → 返回按钮 HTML
 *   initRedPacketModal()                     → 初始化发红包弹窗（调用一次）
 *   renderRedPacket(packetId)                → 渲染红包消息 HTML（异步取详情）
 *   抢红包：点击 .red-packet 元素自动处理
 */

/* 发红包弹窗（全局单例） */
function initRedPacketModal() {
    if (document.getElementById('redpacket-modal')) return;
    var html =
        '<div class="modal-backdrop" id="redpacket-modal" style="display:none">' +
        '<div class="modal" style="max-width:380px"><h3>🧧 发积分红包</h3>' +
        '<div style="text-align:center;margin:10px 0"><div style="font-size:48px">🧧</div></div>' +
        '<label>总金额（积分）</label><input type="number" id="rp-points" min="1" max="10000" value="10">' +
        '<label>红包份数</label><input type="number" id="rp-count" min="1" max="100" value="5">' +
        '<label>祝福语</label><input type="text" id="rp-msg" maxlength="50" value="恭喜发财，大吉大利">' +
        '<p class="form-hint" id="rp-balance">我的积分：加载中…</p>' +
        '<p class="form-note" id="rp-note"></p>' +
        '<div class="modal-actions"><button class="btn" id="rp-cancel" type="button">取消</button>' +
        '<button class="btn btn-blue" id="rp-send" type="button">塞钱进红包</button></div></div></div>';
    document.body.insertAdjacentHTML('beforeend', html);
    var modal = document.getElementById('redpacket-modal');
    var ctxType = null, ctxId = null, onSent = null;

    document.getElementById('rp-cancel').addEventListener('click', function () {
        modal.style.display = 'none';
    });
    modal.addEventListener('click', function (e) {
        if (e.target === modal) modal.style.display = 'none';
    });

    /* 打开弹窗：window.openRedPacket(contextType, contextId, onSentCallback) */
    window.openRedPacket = function (contextType, contextId, callback) {
        ctxType = contextType; ctxId = contextId; onSent = callback || null;
        document.getElementById('rp-note').textContent = '';
        document.getElementById('rp-note').className = 'form-note';
        modal.style.display = 'flex';
        /* 显示余额 */
        myPoints().then(function (p) {
            document.getElementById('rp-balance').textContent = '我的积分：' + p;
        }).catch(function () {
            document.getElementById('rp-balance').textContent = '';
        });
    };

    document.getElementById('rp-send').addEventListener('click', async function () {
        var points = parseInt(document.getElementById('rp-points').value, 10);
        var count = parseInt(document.getElementById('rp-count').value, 10);
        var msg = document.getElementById('rp-msg').value.trim() || '恭喜发财，大吉大利';
        var note = document.getElementById('rp-note');
        if (!points || points < 1) { note.textContent = '金额须大于0'; note.className = 'form-note err'; return; }
        if (!count || count < 1) { note.textContent = '份数须大于0'; note.className = 'form-note err'; return; }
        if (points < count) { note.textContent = '金额不能小于份数'; note.className = 'form-note err'; return; }
        var btn = this;
        btn.disabled = true; btn.textContent = '发送中…';
        try {
            var r = await sb.rpc('send_red_packet', {
                p_total_points: points,
                p_total_count: count,
                p_message: msg,
                p_context_type: ctxType,
                p_context_id: ctxId
            });
            if (r.error) throw new Error(r.error.message);
            modal.style.display = 'none';
            if (onSent) onSent(r.data, { points: points, count: count, message: msg });
        } catch (e) {
            note.textContent = '发送失败：' + (e.message || e);
            note.className = 'form-note err';
        }
        btn.disabled = false; btn.textContent = '塞钱进红包';
    });
}

/* 红包按钮 HTML */
function redPacketButton(contextType, contextId) {
    return '<button class="btn btn-ghost btn-sm" data-rp-send data-ctx="' + esc(contextType) +
        '" data-cid="' + esc(contextId || '') + '">🧧 红包</button>';
}

/* 绑定红包按钮点击（容器内委托） */
function bindRedPacketButtons(container, onSent) {
    (container || document).addEventListener('click', function (e) {
        var btn = e.target.closest('[data-rp-send]');
        if (!btn) return;
        e.preventDefault();
        initRedPacketModal();
        var ctx = btn.getAttribute('data-ctx');
        var cid = btn.getAttribute('data-cid') || null;
        window.openRedPacket(ctx, cid, onSent);
    });
}

/* 渲染红包消息（列表/聊天中的红包卡片） */
async function renderRedPacket(packetId) {
    try {
        var r = await sb.from('red_packets').select('*').eq('id', packetId).single();
        if (r.error || !r.data) return '';
        var p = r.data;
        var done = p.remaining_count <= 0;
        /* 查我是否抢过 */
        var me = await currentUser();
        var claimed = false, myGot = 0;
        if (me) {
            var cr = await sb.from('red_packet_claims').select('points')
                .eq('packet_id', packetId).eq('user_id', me.id).limit(1);
            if (cr.data && cr.data.length) { claimed = true; myGot = cr.data[0].points; }
        }
        var status = done ? '已抢完' : ('剩 ' + p.remaining_count + '/' + p.total_count + ' 份');
        if (claimed) status = '已抢 ' + myGot + ' 积分';
        return '<div class="red-packet' + (done ? ' done' : '') + '" data-rp-id="' + esc(packetId) + '">' +
            '<div class="rp-icon">🧧</div>' +
            '<div class="rp-info"><div class="rp-msg">' + esc(p.message || '恭喜发财') + '</div>' +
            '<div class="rp-status">' + esc(status) + '</div></div></div>';
    } catch (e) {
        return '';
    }
}

/* 抢红包点击（全局委托） */
function bindRedPacketClaim(container) {
    (container || document).addEventListener('click', async function (e) {
        var el = e.target.closest('.red-packet');
        if (!el) return;
        e.preventDefault();
        var pid = el.getAttribute('data-rp-id');
        if (!pid) return;
        try {
            var r = await sb.rpc('claim_red_packet', { p_packet_id: pid });
            if (r.error) throw new Error(r.error.message);
            alert('🎉 抢到 ' + r.data + ' 积分！');
            /* 刷新红包状态 */
            var html = await renderRedPacket(pid);
            if (html) {
                var tmp = document.createElement('div');
                tmp.innerHTML = html;
                var fresh = tmp.firstChild;
                el.parentNode.replaceChild(fresh, el);
            }
        } catch (err) {
            alert('抢红包失败：' + (err.message || err));
        }
    });
}

/* 红包样式 */
var REDPACKET_CSS = [
    '.red-packet{display:flex;align-items:center;gap:10px;background:linear-gradient(135deg,#e03131,#f03e3e);',
    ' border-radius:12px;padding:12px 16px;color:#fff;cursor:pointer;max-width:280px;margin:8px 0;',
    ' box-shadow:0 2px 8px rgba(224,49,49,.35);transition:transform .15s;}',
    '.red-packet:hover{transform:scale(1.03);}',
    '.red-packet.done{background:linear-gradient(135deg,#868e96,#adb5bd);box-shadow:none;}',
    '.red-packet .rp-icon{font-size:36px;}',
    '.red-packet .rp-msg{font-weight:600;font-size:15px;}',
    '.red-packet .rp-status{font-size:12px;opacity:.9;margin-top:2px;}'
].join('\n');
function injectRedPacketCSS() {
    if (document.getElementById('redpacket-css')) return;
    var st = document.createElement('style');
    st.id = 'redpacket-css'; st.textContent = REDPACKET_CSS;
    document.head.appendChild(st);
}
