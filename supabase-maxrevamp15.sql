-- 给现有积分函数加上原因标记（配合 trg_log_points 触发器记明细）

-- 任务奖励
create or replace function claim_task_reward(p_user_task_id uuid)
returns integer as $$
declare
  v_points integer;
  v_uid uuid := auth.uid();
  v_title text;
begin
  select t.points, t.title into v_points, v_title
  from user_tasks ut
  join tasks t on t.id = ut.task_id
  where ut.id = p_user_task_id
    and ut.user_id = v_uid
    and ut.completed = true
    and ut.claimed = false;
  if v_points is null then
    raise exception 'cannot claim';
  end if;
  perform set_config('app.points_reason', '任务奖励：' || coalesce(v_title, ''), true);
  update profiles set points = points + v_points where id = v_uid;
  update user_tasks set claimed = true where id = p_user_task_id;
  return v_points;
end;
$$ language plpgsql security definer;

-- 商城购买
create or replace function purchase_shop_item(p_item_id uuid)
returns boolean as $$
declare
  v_price integer;
  v_uid uuid := auth.uid();
  v_pts integer;
  v_name text;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select price, name into v_price, v_name from shop_items where id = p_item_id and is_active = true;
  if v_price is null then raise exception 'item not found'; end if;
  select points into v_pts from profiles where id = v_uid;
  if v_pts is null or v_pts < v_price then raise exception 'not enough points'; end if;
  if exists (select 1 from user_items where user_id = v_uid and item_id = p_item_id) then
    return true;
  end if;
  perform set_config('app.points_reason', '商城购买：' || coalesce(v_name, ''), true);
  update profiles set points = points - v_price where id = v_uid;
  insert into user_items (user_id, item_id) values (v_uid, p_item_id)
  on conflict (user_id, item_id) do nothing;
  return true;
end;
$$ language plpgsql security definer;

-- 赛事结算
create or replace function settle_contest(p_contest_id uuid)
returns boolean as $$
declare
  v_uid uuid := auth.uid();
  v_creator uuid;
  v_is_admin boolean;
  v_title text;
  r record;
  v_rank int := 0;
  v_bonus int;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select created_by, title into v_creator, v_title from contests where id = p_contest_id;
  if v_creator is null then raise exception 'contest not found'; end if;
  select coalesce(is_admin, false) into v_is_admin from profiles where id = v_uid;
  if v_creator != v_uid and not v_is_admin then raise exception 'not allowed'; end if;
  if (select settled from contests where id = p_contest_id) then raise exception 'already settled'; end if;

  for r in
    select e.user_id, count(v.id) as votes
    from contest_entries e
    left join contest_votes v on v.entry_id = e.id
    where e.contest_id = p_contest_id
    group by e.user_id
    order by votes desc
    limit 3
  loop
    v_rank := v_rank + 1;
    v_bonus := case v_rank when 1 then 100 when 2 then 50 else 30 end;
    perform set_config('app.points_reason', '赛事奖励：' || v_title, true);
    update profiles set points = points + v_bonus where id = r.user_id;
    insert into notifications (user_id, type, ref_id, content)
    values (r.user_id, 'contest_reward', p_contest_id,
      '你在赛事「' || v_title || '」中获得第' || v_rank || '名，奖励 +' || v_bonus || ' 积分');
  end loop;

  update contests set settled = true where id = p_contest_id;
  return true;
end;
$$ language plpgsql security definer;

-- 发红包
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

    perform set_config('app.points_reason', '发出红包', true);
    update profiles set points = points - p_total_points where id = v_uid;

    insert into red_packets (sender_id, total_points, total_count, remaining_points, remaining_count, message, context_type, context_id)
    values (v_uid, p_total_points, p_total_count, p_total_points, p_total_count,
            left(coalesce(p_message, '恭喜发财，大吉大利'), 50), p_context_type, p_context_id)
    returning id into v_id;
    return v_id;
end;
$$ language plpgsql security definer;

-- 抢红包
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

    if v_rp.remaining_count = 1 then
        v_got := v_rp.remaining_points;
    else
        v_max := (v_rp.remaining_points / v_rp.remaining_count) * 2;
        if v_max < 1 then v_max := 1; end if;
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

    perform set_config('app.points_reason', '抢到红包', true);
    update profiles set points = points + v_got where id = v_uid;

    return v_got;
end;
$$ language plpgsql security definer;
