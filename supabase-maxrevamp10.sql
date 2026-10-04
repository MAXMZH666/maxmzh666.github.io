-- MAX社区 v10：8 功能合集 SQL 迁移
-- 执行前确认：均为新增表/列，不影响现有数据

-- ============ 1. 评论楼中楼：comments 加 parent_id ============
alter table comments add column if not exists parent_id uuid references comments(id) on delete cascade;
create index if not exists idx_comments_parent on comments (parent_id);
-- 论坛回帖楼中楼：forum_posts 加 parent_id
alter table forum_posts add column if not exists parent_id uuid references forum_posts(id) on delete cascade;
create index if not exists idx_forum_posts_parent on forum_posts (parent_id);

-- ============ 2. 私信群聊 ============
create table if not exists chat_groups (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    owner_id uuid not null references profiles(id) on delete cascade,
    avatar_url text,
    created_at timestamptz not null default now()
);
create table if not exists chat_group_members (
    group_id uuid not null references chat_groups(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    joined_at timestamptz not null default now(),
    primary key (group_id, user_id)
);
alter table direct_messages add column if not exists group_id uuid references chat_groups(id) on delete cascade;
create index if not exists idx_dm_group on direct_messages (group_id, created_at);
alter table chat_groups enable row level security;
alter table chat_group_members enable row level security;
drop policy if exists "群成员可读群" on chat_groups;
create policy "群成员可读群" on chat_groups for select using (
    exists (select 1 from chat_group_members where group_id = chat_groups.id and user_id = auth.uid())
);
drop policy if exists "群主可建群" on chat_groups;
create policy "群主可建群" on chat_groups for insert with check (auth.uid() = owner_id);
drop policy if exists "群主可改群" on chat_groups;
create policy "群主可改群" on chat_groups for update using (auth.uid() = owner_id);
drop policy if exists "群主可解散" on chat_groups;
create policy "群主可解散" on chat_groups for delete using (auth.uid() = owner_id);
drop policy if exists "群成员列表成员可见" on chat_group_members;
create policy "群成员列表成员可见" on chat_group_members for select using (
    exists (select 1 from chat_group_members m where m.group_id = chat_group_members.group_id and m.user_id = auth.uid())
);
drop policy if exists "群主可拉人" on chat_group_members;
create policy "群主可拉人" on chat_group_members for insert with check (
    exists (select 1 from chat_groups where id = group_id and owner_id = auth.uid())
);
drop policy if exists "成员可退群/群主可踢人" on chat_group_members;
create policy "成员可退群/群主可踢人" on chat_group_members for delete using (
    user_id = auth.uid() or exists (select 1 from chat_groups where id = group_id and owner_id = auth.uid())
);
-- 群聊消息：发送者须是群成员，接收者为群成员
drop policy if exists "群成员可发群消息" on direct_messages;
create policy "群成员可发群消息" on direct_messages for insert with check (
    group_id is null or exists (select 1 from chat_group_members where group_id = direct_messages.group_id and user_id = auth.uid())
);
drop policy if exists "群成员可读群消息" on direct_messages;
create policy "群成员可读群消息" on direct_messages for select using (
    group_id is null or exists (select 1 from chat_group_members where group_id = direct_messages.group_id and user_id = auth.uid())
);

-- ============ 3. 每日签到 ============
create table if not exists checkins (
    user_id uuid not null references profiles(id) on delete cascade,
    check_date date not null,
    points_awarded int not null default 5,
    created_at timestamptz not null default now(),
    primary key (user_id, check_date)
);
alter table checkins enable row level security;
drop policy if exists "签到自己可见" on checkins;
create policy "签到自己可见" on checkins for select using (auth.uid() = user_id);
drop policy if exists "签到自己可写" on checkins;
create policy "签到自己可写" on checkins for insert with check (auth.uid() = user_id);

-- ============ 4. 话题标签 ============
create table if not exists tags (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,
    created_at timestamptz not null default now()
);
create table if not exists work_tags (
    work_id uuid not null references works(id) on delete cascade,
    tag_id uuid not null references tags(id) on delete cascade,
    primary key (work_id, tag_id)
);
create index if not exists idx_work_tags_tag on work_tags (tag_id);
alter table tags enable row level security;
alter table work_tags enable row level security;
drop policy if exists "标签公开可读" on tags;
create policy "标签公开可读" on tags for select using (true);
drop policy if exists "标签登录可建" on tags;
create policy "标签登录可建" on tags for insert with check (auth.uid() is not null);
drop policy if exists "作品标签公开可读" on work_tags;
create policy "作品标签公开可读" on work_tags for select using (true);
drop policy if exists "作者可打标签" on work_tags;
create policy "作者可打标签" on work_tags for insert with check (
    exists (select 1 from works where id = work_id and author_id = auth.uid())
);
drop policy if exists "作者可删标签" on work_tags;
create policy "作者可删标签" on work_tags for delete using (
    exists (select 1 from works where id = work_id and author_id = auth.uid())
);

-- ============ 5. 屏蔽用户 ============
create table if not exists blocks (
    blocker_id uuid not null references profiles(id) on delete cascade,
    blocked_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    check (blocker_id != blocked_id)
);
alter table blocks enable row level security;
drop policy if exists "屏蔽自己管理" on blocks;
create policy "屏蔽自己管理" on blocks for all using (auth.uid() = blocker_id) with check (auth.uid() = blocker_id);

-- ============ 6. 动态feed点赞（作品点赞已存在，只需feed内联操作，无新表） ============
-- 论坛帖子点赞表（如已有则跳过）
create table if not exists thread_likes (
    thread_id uuid not null references forum_threads(id) on delete cascade,
    user_id uuid not null references profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (thread_id, user_id)
);
alter table thread_likes enable row level security;
drop policy if exists "帖子点赞公开可读" on thread_likes;
create policy "帖子点赞公开可读" on thread_likes for select using (true);
drop policy if exists "帖子点赞自己管理" on thread_likes;
create policy "帖子点赞自己管理" on thread_likes for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============ 群聊补丁：receiver_id 允许空 + 触发器跳过群消息 ============
alter table direct_messages alter column receiver_id drop not null;
-- notify_dm 触发器跳过群消息（避免给自己发通知）
do $$
begin
    if exists (select 1 from pg_proc where proname = 'notify_dm') then
        create or replace function notify_dm() returns trigger as $fn$
        begin
            if new.group_id is not null then return new; end if;
            insert into notifications (user_id, type, from_user_id, ref_id)
            values (new.receiver_id, 'dm', new.sender_id, new.id);
            return new;
        end $fn$ language plpgsql security definer;
    end if;
end $$;
