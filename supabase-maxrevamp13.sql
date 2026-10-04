-- 邀请码系统
-- 规则：新人填邀请码注册，双方各得100积分；邀请人按人数解锁里程碑额外奖励

alter table profiles add column if not exists invite_code text unique;
alter table profiles add column if not exists invited_by uuid references profiles(id) on delete set null;

create table if not exists invitations (
    id uuid primary key default gen_random_uuid(),
    inviter_id uuid not null references profiles(id) on delete cascade,
    invitee_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz default now(),
    unique(invitee_id)
);
create index if not exists idx_invitations_inviter on invitations(inviter_id);

create table if not exists invite_milestones (
    inviter_id uuid not null references profiles(id) on delete cascade,
    milestone int not null,
    claimed_at timestamptz default now(),
    primary key (inviter_id, milestone)
);

alter table invitations enable row level security;
alter table invite_milestones enable row level security;
drop policy if exists "邀请记录公开可读" on invitations;
create policy "邀请记录公开可读" on invitations for select using (true);
drop policy if exists "里程碑公开可读" on invite_milestones;
create policy "里程碑公开可读" on invite_milestones for select using (true);

-- 生成唯一邀请码（6位，大写字母+数字，去掉易混淆字符）
create or replace function gen_invite_code() returns text as $$
declare
    v_chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    v_code text;
    v_i int;
begin
    loop
        v_code := '';
        for v_i in 1..6 loop
            v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
        end loop;
        if not exists (select 1 from profiles where invite_code = v_code) then
            return v_code;
        end if;
    end loop;
end;
$$ language plpgsql;

-- 给没有邀请码的老用户补码
do $$
declare r record;
begin
    for r in select id from profiles where invite_code is null loop
        update profiles set invite_code = gen_invite_code() where id = r.id;
    end loop;
end $$;

-- 新用户注册时自动分配邀请码（ profiles insert 触发器）
create or replace function assign_invite_code() returns trigger as $$
begin
    if new.invite_code is null then
        new.invite_code := gen_invite_code();
    end if;
    return new;
end;
$$ language plpgsql;
drop trigger if exists trg_assign_invite_code on profiles;
create trigger trg_assign_invite_code before insert on profiles
    for each row execute function assign_invite_code();

-- 处理邀请：新人注册完成后调用，双方各+100，记录邀请，检查里程碑
-- 里程碑：3人+150，5人+300，10人+800，20人+2000，50人+5000
create or replace function process_invite(p_invite_code text)
returns jsonb as $$
declare
    v_invitee uuid := auth.uid();
    v_inviter uuid;
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

    select id into v_inviter from profiles where invite_code = upper(trim(p_invite_code));
    if v_inviter is null then raise exception '邀请码不存在'; end if;
    if v_inviter = v_invitee then raise exception '不能填写自己的邀请码'; end if;
    if exists (select 1 from invitations where invitee_id = v_invitee) then
        raise exception '你已经使用过邀请码';
    end if;

    -- 记录邀请关系
    insert into invitations (inviter_id, invitee_id) values (v_inviter, v_invitee);
    update profiles set invited_by = v_inviter where id = v_invitee;

    -- 双方各+100
    update profiles set points = points + 100 where id = v_invitee;
    update profiles set points = points + 100 where id = v_inviter;

    -- 检查里程碑
    select count(*) into v_count from invitations where inviter_id = v_inviter;
    for v_i in 1..array_length(v_milestones, 1) loop
        if v_count >= v_milestones[v_i]
           and not exists (select 1 from invite_milestones where inviter_id = v_inviter and milestone = v_milestones[v_i]) then
            insert into invite_milestones (inviter_id, milestone) values (v_inviter, v_milestones[v_i]);
            update profiles set points = points + v_rewards[v_i] where id = v_inviter;
            v_got_milestone := v_milestones[v_i];
        end if;
    end loop;

    return jsonb_build_object('ok', true, 'invited', true, 'milestone', v_got_milestone);
end;
$$ language plpgsql security definer;

-- ========== 商城新增商品（8件） ==========
insert into shop_items (name, item_type, price, item_data, description) values
('樱吹雪', 'background', 350, 'linear-gradient(135deg,#3d1a2e 0%,#7a2e4e 55%,#2e0f1a 100%)', '粉色樱花主题个人主页背景'),
('深渊之瞳', 'background', 350, 'linear-gradient(135deg,#1a0b3d 0%,#2e0e5e 55%,#0f0a2e 100%)', '深邃紫色个人主页背景'),
('邀请大使', 'title', 400, '邀请大使', '邀请好友的专属称号'),
('传奇光环', 'frame', 500, 'frame-legend', '橙色传奇头像框'),
('星空穹顶', 'background', 600, 'animated:galaxy', '动态星空个人主页背景'),
('社区传说', 'badge', 600, '🏆', '社区传说徽章'),
('至尊', 'title', 800, '至尊', '至高无上的称号'),
('钻石之心', 'frame', 800, 'frame-diamond', '钻石闪耀头像框');

-- ========== 成长任务高阶梯度 ==========
-- 需要确认 tasks 表有 task_type 列（daily/once）
insert into tasks (title, description, action_type, target_count, points, task_type, is_active) values
('点赞之路 II', '作品累计获得 50 个点赞', 'work_liked', 50, 80, 'once', true),
('点赞之路 III', '作品累计获得 200 个点赞', 'work_liked', 200, 200, 'once', true),
('粉丝之路 II', '获得 20 个粉丝', 'followers', 20, 80, 'once', true),
('粉丝之路 III', '获得 100 个粉丝', 'followers', 100, 250, 'once', true),
('创作之路 III', '累计发布 20 个作品', 'publish_work', 20, 200, 'once', true),
('创作之路 IV', '累计发布 50 个作品', 'publish_work', 50, 500, 'once', true),
('论坛之路 II', '累计发表 20 个论坛主题', 'post_thread', 20, 120, 'once', true),
('论坛之路 III', '累计发表 50 个论坛主题', 'post_thread', 50, 300, 'once', true);
