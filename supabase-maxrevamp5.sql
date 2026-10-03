/* ===== MAX社区 supabase-maxrevamp5.sql =====
   个人主页留言板 + 工作室内部讨论室。
   分两段执行，每段确认 Success。
*/

/* ---------- 第一段：留言板 ---------- */
create table if not exists profile_guestbook (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 2000),
  created_at timestamptz default now()
);
create index if not exists idx_guestbook_profile on profile_guestbook(profile_id, created_at desc);
alter table profile_guestbook enable row level security;
drop policy if exists "guestbook 公开可读" on profile_guestbook;
create policy "guestbook 公开可读" on profile_guestbook for select using (true);
drop policy if exists "guestbook 登录可留" on profile_guestbook;
create policy "guestbook 登录可留" on profile_guestbook for insert with check (auth.uid() = user_id);
drop policy if exists "guestbook 作者可删" on profile_guestbook;
create policy "guestbook 作者可删" on profile_guestbook for delete using (
  auth.uid() = user_id or auth.uid() = profile_id or is_site_admin()
);

/* ---------- 第二段：工作室内部讨论室（仅成员可见） ---------- */
create table if not exists studio_discussions (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references studios(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 2000),
  created_at timestamptz default now()
);
create index if not exists idx_discuss_studio on studio_discussions(studio_id, created_at desc);
alter table studio_discussions enable row level security;
drop policy if exists "discuss 成员可读" on studio_discussions;
create policy "discuss 成员可读" on studio_discussions for select using (
  is_site_admin() or
  exists (select 1 from studio_members m where m.studio_id = studio_discussions.studio_id and m.user_id = auth.uid())
);
drop policy if exists "discuss 成员可发" on studio_discussions;
create policy "discuss 成员可发" on studio_discussions for insert with check (
  auth.uid() = user_id and (
    is_site_admin() or
    exists (select 1 from studio_members m where m.studio_id = studio_discussions.studio_id and m.user_id = auth.uid())
  )
);
drop policy if exists "discuss 作者管理可删" on studio_discussions;
create policy "discuss 作者管理可删" on studio_discussions for delete using (
  auth.uid() = user_id or is_site_admin() or
  exists (select 1 from studio_members m where m.studio_id = studio_discussions.studio_id
    and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);
