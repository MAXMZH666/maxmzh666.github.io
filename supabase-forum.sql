/* 社区真论坛 v1（2026-10-03）
* 执行方式：Supabase Dashboard → SQL Editor，分~逐段粘贴执行
* （Monaco 粘贴超长 SQL 会错乱，勿一次性全粘）
*/

/* ================= 建表 ================= */
create table if not exists forum_categories (
id uuid primary key default gen_random_uuid(),
name text not null,
description text default '',
icon text default '💬',
sort_order int default 0,
created_at timestamptz default now()
);

create table if not exists forum_threads (
id uuid primary key default gen_random_uuid(),
category_id uuid references forum_categories(id) on delete cascade,
author_id uuid references profiles(id) on delete cascade,
title text not null,
created_at timestamptz default now(),
updated_at timestamptz default now(),
views int not null default 0,
reply_count int not null default 0,
is_pinned boolean not null default false,
is_locked boolean not null default false
);

create table if not exists forum_posts (
id uuid primary key default gen_random_uuid(),
thread_id uuid references forum_threads(id) on delete cascade,
author_id uuid references profiles(id) on delete cascade,
content text not null,
created_at timestamptz default now(),
updated_at timestamptz default now()
);

/* ================= 索引 + RLS ================= */
create index if not exists idx_threads_category on forum_threads(category_id, updated_at desc);
create index if not exists idx_threads_author on forum_threads(author_id);
create index if not exists idx_posts_thread on forum_posts(thread_id, created_at);

alter table forum_categories enable row level security;
alter table forum_threads enable row level security;
alter table forum_posts enable row level security;

drop policy if exists "版块公开读" on forum_categories;
create policy "版块公开读" on forum_categories for select using (true);

drop policy if exists "主题公开读" on forum_threads;
create policy "主题公开读" on forum_threads for select using (true);
drop policy if exists "登录可发帖" on forum_threads;
create policy "登录可发帖" on forum_threads for insert
with check (auth.uid() = author_id);
drop policy if exists "作者可改自己主题" on forum_threads;
create policy "作者可改自己主题" on forum_threads for update
using (auth.uid() = author_id) with check (auth.uid() = author_id);
drop policy if exists "作者或管理员可删主题" on forum_threads;
create policy "作者或管理员可删主题" on forum_threads for delete using (
auth.uid() = author_id
or exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_admin = true)
);
drop policy if exists "管理员可管理主题" on forum_threads;
create policy "管理员可管理主题" on forum_threads for update using (
exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_admin = true)
);

drop policy if exists "回帖公开读" on forum_posts;
create policy "回帖公开读" on forum_posts for select using (true);
drop policy if exists "登录可回帖" on forum_posts;
create policy "登录可回帖" on forum_posts for insert
with check (auth.uid() = author_id);
drop policy if exists "作者可改自己回帖" on forum_posts;
create policy "作者可改自己回帖" on forum_posts for update
using (auth.uid() = author_id) with check (auth.uid() = author_id);
drop policy if exists "作者或管理员可删回帖" on forum_posts;
create policy "作者或管理员可删回帖" on forum_posts for delete using (
auth.uid() = author_id
or exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_admin = true)
);

/* ================= 种子版块 ================= */
insert into forum_categories (name, description, icon, sort_order) values
('综合讨论', '聊游戏、聊创作，什么都可以', '💬', 1),
('作品求助', '作品出 bug 了？来这里问', '❓', 2),
('建议反馈', '给社区提建议、报 bug', '💡', 3),
('灌水乐园', '轻松闲聊区', '🎉', 4)
on conflict do nothing;

/* ================= 计数触发器 + 回复通知 ================= */
alter table notifications add column if not exists thread_id uuid references forum_threads(id) on delete cascade;

create or replace function forum_post_count_upd() returns trigger as $$
begin
if TG_OP = 'INSERT' then
update forum_threads set reply_count = reply_count + 1, updated_at = now() where id = NEW.thread_id;
elsif TG_OP = 'DELETE' then
update forum_threads set reply_count = greatest(reply_count - 1, 0) where id = OLD.thread_id;
end if;
return null;
exception when others then return null;
end; $$ language plpgsql security definer;

drop trigger if exists trg_forum_post_count on forum_posts;
create trigger trg_forum_post_count
after insert or delete on forum_posts
for each row execute function forum_post_count_upd();

/* 有人回帖 → 通知楼主（异常不影响主流程） */
create or replace function notify_forum_reply() returns trigger as $$
declare t_author uuid;
begin
select author_id into t_author from forum_threads where id = NEW.thread_id;
if t_author is not null and t_author <> NEW.author_id then
insert into notifications (user_id, from_user_id, type, thread_id)
values (t_author, NEW.author_id, 'reply', NEW.thread_id);
end if;
return NEW;
exception when others then return NEW;
end; $$ language plpgsql security definer;

drop trigger if exists trg_notify_forum_reply on forum_posts;
create trigger trg_notify_forum_reply
after insert on forum_posts
for each row execute function notify_forum_reply();

/* 浏览量自增（前端调用） */
create or replace function increment_thread_views(tid uuid) returns void as $$
begin
update forum_threads set views = views + 1 where id = tid;
end; $$ language plpgsql security definer;
