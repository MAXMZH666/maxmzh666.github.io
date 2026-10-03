-- 社区第九期：工作室
-- 在 Supabase SQL Editor 中执行

-- 1. 工作室表
create table if not exists studios (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text default '',
  avatar_url text,
  owner_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz default now()
);
create index if not exists idx_studios_owner on studios(owner_id);

-- 2. 成员表
create table if not exists studio_members (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references studios(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz default now(),
  unique(studio_id, user_id)
);
create index if not exists idx_studio_members_studio on studio_members(studio_id);
create index if not exists idx_studio_members_user on studio_members(user_id);

-- 3. 工作室作品表
create table if not exists studio_works (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references studios(id) on delete cascade,
  work_id uuid not null references works(id) on delete cascade,
  added_by uuid not null references profiles(id) on delete cascade,
  added_at timestamptz default now(),
  unique(studio_id, work_id)
);
create index if not exists idx_studio_works_studio on studio_works(studio_id);

-- 4. RLS
alter table studios enable row level security;
alter table studio_members enable row level security;
alter table studio_works enable row level security;

drop policy if exists "studios 公开可读" on studios;
create policy "studios 公开可读" on studios for select using (true);
drop policy if exists "studios 登录可创建" on studios;
create policy "studios 登录可创建" on studios for insert with check (auth.uid() = owner_id);
drop policy if exists "studios 创建者可改" on studios;
create policy "studios 创建者可改" on studios for update using (auth.uid() = owner_id);
drop policy if exists "studios 创建者可删" on studios;
create policy "studios 创建者可删" on studios for delete using (auth.uid() = owner_id);

drop policy if exists "members 公开可读" on studio_members;
create policy "members 公开可读" on studio_members for select using (true);
drop policy if exists "members 可加入" on studio_members;
create policy "members 可加入" on studio_members for insert with check (
  auth.uid() = user_id or
  exists (select 1 from studio_members m where m.studio_id = studio_members.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'admin'))
);
drop policy if exists "members 可退出或被管理" on studio_members;
create policy "members 可退出或被管理" on studio_members for delete using (
  auth.uid() = user_id or
  exists (select 1 from studio_members m where m.studio_id = studio_members.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'admin'))
);

drop policy if exists "studio_works 公开可读" on studio_works;
create policy "studio_works 公开可读" on studio_works for select using (true);
drop policy if exists "studio_works 成员可添加" on studio_works;
create policy "studio_works 成员可添加" on studio_works for insert with check (
  exists (select 1 from studio_members m where m.studio_id = studio_works.studio_id and m.user_id = auth.uid())
);
drop policy if exists "studio_works 可移除" on studio_works;
create policy "studio_works 可移除" on studio_works for delete using (
  auth.uid() = added_by or
  exists (select 1 from studio_members m where m.studio_id = studio_works.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'admin'))
);

-- 5. 创建工作室时自动把创建者设为 owner 成员
create or replace function add_studio_owner()
returns trigger as $$
begin
  insert into studio_members (studio_id, user_id, role)
  values (NEW.id, NEW.owner_id, 'owner')
  on conflict (studio_id, user_id) do nothing;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_add_studio_owner on studios;
create trigger trg_add_studio_owner
after insert on studios
for each row
execute function add_studio_owner();
