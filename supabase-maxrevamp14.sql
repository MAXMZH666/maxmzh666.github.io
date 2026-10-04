-- 邀请奖励通知 + 积分明细系统

-- 1. notifications 加 content 列（存通知文案）
alter table notifications add column if not exists content text;

-- 2. 积分明细表
create table if not exists point_transactions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references profiles(id) on delete cascade,
    amount int not null,
    balance_after int not null,
    reason text not null default '积分变动',
    created_at timestamptz default now()
);
create index if not exists idx_point_tx_user on point_transactions(user_id, created_at desc);

alter table point_transactions enable row level security;
drop policy if exists "只能看自己的积分明细" on point_transactions;
create policy "只能看自己的积分明细" on point_transactions
    for select using (auth.uid() = user_id);

-- 3. 积分变动自动记录触发器
-- 用法：在改积分前执行 perform set_config('app.points_reason', '原因', true);
create or replace function log_points_change() returns trigger as $$
declare
    v_reason text;
begin
    if old.points is distinct from new.points then
        v_reason := current_setting('app.points_reason', true);
        if v_reason is null or v_reason = '' then v_reason := '积分变动'; end if;
        insert into point_transactions (user_id, amount, balance_after, reason)
        values (new.id, new.points - old.points, new.points, v_reason);
        perform set_config('app.points_reason', '', true);
    end if;
    return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_log_points on profiles;
create trigger trg_log_points after update of points on profiles
    for each row execute function log_points_change();

-- 4. 更新 process_invite：加通知 + 积分原因
create or replace function process_invite(p_invite_code text)
returns jsonb as $$
declare
    v_invitee uuid := auth.uid();
    v_inviter uuid;
    v_inviter_name text;
    v_invitee_name text;
    v_count int;
    v_milestones int[] := array[3,5,10,20,50];
    v_rewards int[] := array[150,300,800,2000,5000];
    v_i int;
    v_got_milestone int := 0;
begin
    if v_invitee is null then raise exception 'not logged in'; end if;
    if p_invite_code is null or p_invite_code = '' then
        return jsonb_build_object('ok', true, 'invited', false);
    end if;

    select id, username into v_inviter, v_inviter_name from profiles where invite_code = upper(trim(p_invite_code));
    if v_inviter is null then raise exception '邀请码不存在'; end if;
    if v_inviter = v_invitee then raise exception '不能填写自己的邀请码'; end if;
    if exists (select 1 from invitations where invitee_id = v_invitee) then
        raise exception '你已经使用过邀请码';
    end if;
    select username into v_invitee_name from profiles where id = v_invitee;

    insert into invitations (inviter_id, invitee_id) values (v_inviter, v_invitee);
    update profiles set invited_by = v_inviter where id = v_invitee;

    -- 双方各+100（带原因，会自动记明细）
    perform set_config('app.points_reason', '邀请奖励', true);
    update profiles set points = points + 100 where id = v_invitee;
    perform set_config('app.points_reason', '邀请奖励', true);
    update profiles set points = points + 100 where id = v_inviter;

    -- 通知双方
    insert into notifications (user_id, type, from_user_id, content)
    values (v_invitee, 'invite_reward', v_inviter, '🎉 你使用邀请码注册成功，获得 100 积分！');
    insert into notifications (user_id, type, from_user_id, content)
    values (v_inviter, 'invite_reward', v_invitee, '🎉 ' || coalesce(v_invitee_name, '好友') || ' 通过你的邀请码注册，你获得 100 积分！');

    -- 检查里程碑
    select count(*) into v_count from invitations where inviter_id = v_inviter;
    for v_i in 1..array_length(v_milestones, 1) loop
        if v_count >= v_milestones[v_i]
           and not exists (select 1 from invite_milestones where inviter_id = v_inviter and milestone = v_milestones[v_i]) then
            insert into invite_milestones (inviter_id, milestone) values (v_inviter, v_milestones[v_i]);
            perform set_config('app.points_reason', '邀请里程碑奖励', true);
            update profiles set points = points + v_rewards[v_i] where id = v_inviter;
            insert into notifications (user_id, type, content)
            values (v_inviter, 'invite_milestone', '🎉 邀请达到 ' || v_milestones[v_i] || ' 人，里程碑奖励 +' || v_rewards[v_i] || ' 积分！');
            v_got_milestone := v_milestones[v_i];
        end if;
    end loop;

    return jsonb_build_object('ok', true, 'invited', true, 'milestone', v_got_milestone);
end;
$$ language plpgsql security definer;
