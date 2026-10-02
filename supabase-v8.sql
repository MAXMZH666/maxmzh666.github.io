-- ============================================================
-- MAXMZH 游戏社区 v8：管理员、网站类型、草稿箱
-- 在 Supabase 后台 SQL Editor 里完整执行一次即可（可重复执行）
-- ============================================================

-- 1. 管理员标记（站长设为管理员）
alter table profiles add column if not exists is_admin boolean not null default false;
update profiles set is_admin = true
where id = (select id from auth.users where email = '2926357395@qq.com');

-- 2. 网站类型：works / work_versions 加 site_url
alter table works add column if not exists site_url text;
alter table work_versions add column if not exists site_url text;

-- 3. work_type 增加 website
DO $$ DECLARE cname text; BEGIN
  SELECT conname INTO cname FROM pg_constraint
  WHERE conrelid = 'works'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%work_type%';
  IF cname IS NOT NULL THEN
    EXECUTE 'alter table works drop constraint ' || quote_ident(cname);
  END IF;
END $$;
ALTER TABLE works DROP CONSTRAINT IF EXISTS works_work_type_check;
alter table works add constraint works_work_type_check
  check (work_type in ('scratch','python','cpp','apk','windows','linux','website'));

-- 4. 草稿箱（未发布的作品，保存在个人名下）
create table if not exists drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  work_type text not null default 'scratch' check (work_type in ('scratch','python','cpp')),
  title text not null default '未命名草稿',
  description text not null default '',
  category text not null default '游戏',
  code text,
  sb3_url text,
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);
alter table drafts enable row level security;

drop policy if exists "drafts 本人可读" on drafts;
create policy "drafts 本人可读" on drafts
  for select using (auth.uid() = user_id);
drop policy if exists "drafts 本人可增" on drafts;
create policy "drafts 本人可增" on drafts
  for insert with check (auth.uid() = user_id);
drop policy if exists "drafts 本人可改" on drafts;
create policy "drafts 本人可改" on drafts
  for update using (auth.uid() = user_id);
drop policy if exists "drafts 本人可删" on drafts;
create policy "drafts 本人可删" on drafts
  for delete using (auth.uid() = user_id);

-- 5. 管理员 RLS：看举报、删作品、删评论
drop policy if exists "reports 管理员可读" on reports;
create policy "reports 管理员可读" on reports
  for select using (
    exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_admin = true)
  );

drop policy if exists "works 管理员可删" on works;
create policy "works 管理员可删" on works
  for delete using (
    exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_admin = true)
  );

drop policy if exists "comments 管理员可删" on comments;
create policy "comments 管理员可删" on comments
  for delete using (
    exists (select 1 from profiles where profiles.id = auth.uid() and profiles.is_admin = true)
  );
