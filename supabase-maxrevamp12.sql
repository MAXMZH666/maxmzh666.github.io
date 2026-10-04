-- 积分红包系统
-- 上下文：comment（作品/帖子评论区）、dm（私聊）、studio（工作室讨论室）、group（群聊）

create table if not exists red_packets (
    id uuid primary key default gen_random_uuid(),
    sender_id uuid not null references profiles(id) on delete cascade,
    total_points int not null check (total_points > 0),
    total_count int not null check (total_count > 0),
    remaining_points int not null,
    remaining_count int not null,
    message text default '恭喜发财，大吉大利',
    context_type text not null check (context_type in ('comment','dm','studio','group')),
    context_id uuid,
    created_at timestamptz default now(),
    expires_at timestamptz default now() + interval '24 hours'
);
create index if not exists idx_red_packets_ctx on red_packets(context_type, context_id);
create index if not exists idx_red_packets_sender on red_packets(sender_id);

create table if not exists red_packet_claims (
    id uuid primary key default gen_random_uuid(),
    packet_id uuid not null references red_packets(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    points int not null check (points > 0),
    claimed_at timestamptz default now(),
    unique(packet_id, user_id)
);
create index if not exists idx_red_claims_packet on red_packet_claims(packet_id);

alter table red_packets enable row level security;
alter table red_packet_claims enable row level security;

drop policy if exists "红包公开可读" on red_packets;
create policy "红包公开可读" on red_packets for select using (true);
drop policy if exists "红包领取记录公开可读" on red_packet_claims;
create policy "红包领取记录公开可读" on red_packet_claims for select using (true);
-- 写入走 security definer 函数，不开放直接 insert

/* 发红包：扣积分，建红包 */
create or replace function send_red_packet(
    p_total_points int,
    p_total_count int,
    p_message text,
    p_context_type text,
    p_context_id uuid
) returns uuid as $$
declare
    v_uid uuid := auth.uid();
    v_balance int;
    v_id uuid;
begin
    if v_uid is null then raise exception 'not logged in'; end if;
    if p_total_points is null or p_total_points < 1 then raise exception '金额须大于0'; end if;
    if p_total_count is null or p_total_count < 1 then raise exception '份数须大于0'; end if;
    if p_total_points > 10000 then raise exception '单次最多10000积分'; end if;
    if p_total_count > 100 then raise exception '单次最多100份'; end if;
    if p_total_points < p_total_count then raise exception '金额不能小于份数（每份至少1积分）'; end if;
    if p_context_type not in ('comment','dm','studio','group') then raise exception 'bad context'; end if;

    select points into v_balance from profiles where id = v_uid;
    if v_balance is null then raise exception 'profile not found'; end if;
    if v_balance < p_total_points then raise exception '积分不足'; end if;

    update profiles set points = points - p_total_points where id = v_uid;

    insert into red_packets (sender_id, total_points, total_count, remaining_points, remaining_count, message, context_type, context_id)
    values (v_uid, p_total_points, p_total_count, p_total_points, p_total_count,
            left(coalesce(p_message, '恭喜发财，大吉大利'), 50), p_context_type, p_context_id)
    returning id into v_id;
    return v_id;
end;
$$ language plpgsql security definer;

/* 抢红包：微信式随机，每人至少1积分 */
create or replace function claim_red_packet(p_packet_id uuid)
returns int as $$
declare
    v_uid uuid := auth.uid();
    v_rp record;
    v_got int;
    v_max int;
begin
    if v_uid is null then raise exception 'not logged in'; end if;

    select * into v_rp from red_packets where id = p_packet_id for update;
    if not found then raise exception '红包不存在'; end if;
    if v_rp.expires_at < now() then raise exception '红包已过期'; end if;
    if v_rp.remaining_count <= 0 or v_rp.remaining_points <= 0 then raise exception '红包已抢完'; end if;
    if exists (select 1 from red_packet_claims where packet_id = p_packet_id and user_id = v_uid) then
        raise exception '你已经抢过了';
    end if;

    /* 随机算法：最后一份拿剩余全部，其他随机 1 ~ 剩余均值*2 */
    if v_rp.remaining_count = 1 then
        v_got := v_rp.remaining_points;
    else
        v_max := (v_rp.remaining_points / v_rp.remaining_count) * 2;
        if v_max < 1 then v_max := 1; end if;
        /* 保证剩余够分给剩下的人（每人至少1） */
        if v_max > v_rp.remaining_points - v_rp.remaining_count + 1 then
            v_max := v_rp.remaining_points - v_rp.remaining_count + 1;
        end if;
        v_got := 1 + floor(random() * v_max);
    end if;

    update red_packets
    set remaining_points = remaining_points - v_got,
        remaining_count = remaining_count - 1
    where id = p_packet_id;

    insert into red_packet_claims (packet_id, user_id, points)
    values (p_packet_id, v_uid, v_got);

    update profiles set points = points + v_got where id = v_uid;

    return v_got;
end;
$$ language plpgsql security definer;
