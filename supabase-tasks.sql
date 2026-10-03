-- 社区第五期：任务与积分体系
-- 在 Supabase SQL Editor 中执行

-- 1. profiles 加积分列
alter table profiles add column if not exists points integer not null default 0;

-- 2. 任务定义表
create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text default '',
  points integer not null default 0,
  task_type text not null default 'daily',   -- daily 每日 | once 一次性
  action_type text not null,                  -- login, publish_work, like_work, comment, post_thread, follow_user, profile_complete, work_liked, followers
  target_count integer not null default 1,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz default now()
);

-- 3. 用户任务进度表
create table if not exists user_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  task_id uuid not null references tasks(id) on delete cascade,
  progress integer not null default 0,
  completed boolean not null default false,
  claimed boolean not null default false,
  task_date date,                              -- 每日任务的日期；一次性任务为 null
  completed_at timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_user_tasks_user on user_tasks(user_id);
create index if not exists idx_user_tasks_task on user_tasks(task_id);

-- 4. RLS
alter table tasks enable row level security;
alter table user_tasks enable row level security;

drop policy if exists "tasks 公开可读" on tasks;
create policy "tasks 公开可读" on tasks for select using (true);

drop policy if exists "user_tasks 本人可读" on user_tasks;
create policy "user_tasks 本人可读" on user_tasks for select using (auth.uid() = user_id);
drop policy if exists "user_tasks 本人可写" on user_tasks;
create policy "user_tasks 本人可写" on user_tasks for insert with check (auth.uid() = user_id);
drop policy if exists "user_tasks 本人可更新" on user_tasks;
create policy "user_tasks 本人可更新" on user_tasks for update using (auth.uid() = user_id);

-- profiles 的 points 由领取函数更新，需要允许本人更新 points
-- （已有 update 策略的话这条可跳过；保留以防万一）
-- 注意：claim_task_reward 是 SECURITY DEFINER，不依赖这条

-- 5. 领取奖励函数（原子操作，防刷）
create or replace function claim_task_reward(p_user_task_id uuid)
returns integer as $$
declare
  v_points integer;
  v_uid uuid := auth.uid();
begin
  select t.points into v_points
  from user_tasks ut
  join tasks t on t.id = ut.task_id
  where ut.id = p_user_task_id
    and ut.user_id = v_uid
    and ut.completed = true
    and ut.claimed = false;
  if v_points is null then
    raise exception 'cannot claim';
  end if;
  update profiles set points = points + v_points where id = v_uid;
  update user_tasks set claimed = true where id = p_user_task_id;
  return v_points;
end;
$$ language plpgsql security definer;

-- 6. 种子任务
insert into tasks (title, description, points, task_type, action_type, target_count, sort_order) values
-- 每日任务
('每日登录', '每天访问社区并登录', 5, 'daily', 'login', 1, 1),
('发布作品', '每天发布 1 个作品', 20, 'daily', 'publish_work', 1, 2),
('点赞达人', '每天给 3 个作品点赞', 10, 'daily', 'like_work', 3, 3),
('活跃评论', '每天发表 2 条评论', 10, 'daily', 'comment', 2, 4),
('论坛发声', '每天发表 1 个论坛主题', 15, 'daily', 'post_thread', 1, 5),
('结识新朋友', '每天关注 1 位作者', 5, 'daily', 'follow_user', 1, 6),
-- 成长任务（一次性）
('初露锋芒', '发布第一个作品', 50, 'once', 'publish_work', 1, 11),
('创作达人', '累计发布 5 个作品', 80, 'once', 'publish_work', 5, 12),
('人气之星', '作品累计获得 10 个点赞', 30, 'once', 'work_liked', 10, 13),
('深受喜爱', '获得 5 个粉丝', 30, 'once', 'followers', 5, 14),
('论坛达人', '累计发表 5 个论坛主题', 40, 'once', 'post_thread', 5, 15),
('完善资料', '设置头像和个人简介', 20, 'once', 'profile_complete', 1, 16)
on conflict do nothing;
