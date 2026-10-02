-- ============================================================
-- MAXMZH 游戏社区 v6：收藏 + 作品版本历史
-- 在 Supabase 后台 SQL Editor 里完整执行一次即可（可重复执行）
-- ============================================================

-- 1. 收藏表
create table if not exists favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  work_id uuid not null references works(id) on delete cascade,
  created_at timestamptz default now(),
  unique (user_id, work_id)
);
alter table favorites enable row level security;

drop policy if exists "favorites 本人可读" on favorites;
create policy "favorites 本人可读" on favorites
  for select using (auth.uid() = user_id);

drop policy if exists "favorites 本人可增" on favorites;
create policy "favorites 本人可增" on favorites
  for insert with check (auth.uid() = user_id);

drop policy if exists "favorites 本人可删" on favorites;
create policy "favorites 本人可删" on favorites
  for delete using (auth.uid() = user_id);

-- 2. 作品版本历史表（每次编辑先快照当前版本）
create table if not exists work_versions (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references works(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  version_no int not null,
  title text,
  description text,
  category text,
  work_type text,
  code text,
  sb3_url text,
  apk_url text,
  screenshots text[] not null default '{}',
  cover_url text,
  created_at timestamptz default now(),
  unique (work_id, version_no)
);
alter table work_versions enable row level security;

drop policy if exists "versions 公开可读" on work_versions;
create policy "versions 公开可读" on work_versions
  for select using (true);

drop policy if exists "versions 作者可增" on work_versions;
create policy "versions 作者可增" on work_versions
  for insert with check (auth.uid() = author_id);
