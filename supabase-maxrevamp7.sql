/* ===== MAX社区 supabase-maxrevamp7.sql =====
   全站搜索(无需新表) + 私信 + @提及通知 + 作品合集。
   数据看板用现有 works.views/likes，无需新表。
   一段执行，确认 Success。
*/

/* ---------- 私信 ---------- */
create table if not exists direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references profiles(id) on delete cascade,
  receiver_id uuid not null references profiles(id) on delete cascade,
  content text not null check (char_length(content) <= 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
alter table direct_messages enable row level security;
drop policy if exists "dm 参与者可读" on direct_messages;
create policy "dm 参与者可读" on direct_messages
  for select using (auth.uid() = sender_id or auth.uid() = receiver_id);
drop policy if exists "dm 登录可发" on direct_messages;
create policy "dm 登录可发" on direct_messages
  for insert with check (auth.uid() = sender_id);
drop policy if exists "dm 接收者可标已读" on direct_messages;
create policy "dm 接收者可标已读" on direct_messages
  for update using (auth.uid() = receiver_id) with check (auth.uid() = receiver_id);
create index if not exists idx_dm_pair on direct_messages (least(sender_id, receiver_id), greatest(sender_id, receiver_id), created_at);

/* 私信通知：发私信时给接收者发通知（复用 notifications 表） */
create or replace function notify_dm() returns trigger as $$
begin
  insert into notifications (user_id, type, from_user_id, content, ref_id)
  values (new.receiver_id, 'dm', new.sender_id, '发来一条私信', new.id);
  return new;
exception when others then
  return new;
end;
$$ language plpgsql security definer;
drop trigger if exists trg_notify_dm on direct_messages;
create trigger trg_notify_dm after insert on direct_messages
  for each row execute function notify_dm();

/* ---------- @提及通知 ---------- */
create or replace function send_mention(p_user_id uuid, p_from_user_id uuid, p_content text, p_ref_id uuid, p_ref_type text)
returns void as $$
begin
  if p_user_id = p_from_user_id then return; end if;
  insert into notifications (user_id, type, from_user_id, content, ref_id)
  values (p_user_id, 'mention', p_from_user_id, p_content, p_ref_id);
exception when others then
  null;
end;
$$ language plpgsql security definer;

/* ---------- 作品合集 ---------- */
create table if not exists collections (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id) on delete cascade,
  title text not null check (char_length(title) <= 40),
  description text check (char_length(description) <= 500),
  cover_url text,
  created_at timestamptz not null default now()
);
alter table collections enable row level security;
drop policy if exists "collections 公开可读" on collections;
create policy "collections 公开可读" on collections for select using (true);
drop policy if exists "collections 登录可建" on collections;
create policy "collections 登录可建" on collections for insert with check (auth.uid() = owner_id);
drop policy if exists "collections 主人可改" on collections;
create policy "collections 主人可改" on collections for update using (auth.uid() = owner_id or is_site_admin());
drop policy if exists "collections 主人可删" on collections;
create policy "collections 主人可删" on collections for delete using (auth.uid() = owner_id or is_site_admin());

create table if not exists collection_works (
  collection_id uuid not null references collections(id) on delete cascade,
  work_id uuid not null references works(id) on delete cascade,
  position int not null default 0,
  added_at timestamptz not null default now(),
  primary key (collection_id, work_id)
);
alter table collection_works enable row level security;
drop policy if exists "cw 公开可读" on collection_works;
create policy "cw 公开可读" on collection_works for select using (true);
drop policy if exists "cw 合集主人可改" on collection_works;
create policy "cw 合集主人可改" on collection_works for all using (
  exists (select 1 from collections where collections.id = collection_id and (collections.owner_id = auth.uid() or is_site_admin()))
) with check (
  exists (select 1 from collections where collections.id = collection_id and (collections.owner_id = auth.uid() or is_site_admin()))
);
create index if not exists idx_cw_collection on collection_works (collection_id, position);
