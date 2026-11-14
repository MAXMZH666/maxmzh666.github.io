-- MAX论坛功能补齐迁移（2026-11-14）
-- 1) 回帖编辑标记列
alter table public.forum_posts add column if not exists edited_at timestamptz;

-- 2) 回帖点赞表（幂等三件套：GRANT + RLS + policy）
create table if not exists public.forum_post_likes (
  post_id uuid not null references public.forum_posts(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
grant select on public.forum_post_likes to anon, authenticated;
grant insert, delete on public.forum_post_likes to authenticated;
alter table public.forum_post_likes enable row level security;
drop policy if exists "likes_read" on public.forum_post_likes;
create policy "likes_read" on public.forum_post_likes for select using (true);
drop policy if exists "likes_insert_own" on public.forum_post_likes;
create policy "likes_insert_own" on public.forum_post_likes for insert with check (auth.uid() = user_id);
drop policy if exists "likes_delete_own" on public.forum_post_likes;
create policy "likes_delete_own" on public.forum_post_likes for delete using (auth.uid() = user_id);

-- 3) 主题收藏表（仅本人可见自己的收藏）
create table if not exists public.forum_favorites (
  thread_id uuid not null references public.forum_threads(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);
grant select, insert, delete on public.forum_favorites to authenticated;
alter table public.forum_favorites enable row level security;
drop policy if exists "fav_read_own" on public.forum_favorites;
create policy "fav_read_own" on public.forum_favorites for select using (auth.uid() = user_id);
drop policy if exists "fav_insert_own" on public.forum_favorites;
create policy "fav_insert_own" on public.forum_favorites for insert with check (auth.uid() = user_id);
drop policy if exists "fav_delete_own" on public.forum_favorites;
create policy "fav_delete_own" on public.forum_favorites for delete using (auth.uid() = user_id);

-- 4) 作者可编辑自己的回帖与主题（与既有管理员策略叠加，permissive 为 OR）
drop policy if exists "posts_update_own" on public.forum_posts;
create policy "posts_update_own" on public.forum_posts for update using (auth.uid() = author_id) with check (auth.uid() = author_id);
drop policy if exists "threads_update_own" on public.forum_threads;
create policy "threads_update_own" on public.forum_threads for update using (auth.uid() = author_id) with check (auth.uid() = author_id);
