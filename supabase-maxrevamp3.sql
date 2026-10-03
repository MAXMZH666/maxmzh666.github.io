/* ===== MAX社区第三轮改版 supabase-maxrevamp3.sql =====
   1. 工作室/赛事类别列
   2. 个人偏好设置（profiles.settings）
   3. 草稿支持 website 类型
   4. 通知表扩展 studio_id / ref_id
   5. 入室申请表 + 邀请表 + RLS
   6. 管理员判断函数 + 申请/邀请 RPC（security definer，原子操作+发通知）
   建议分段执行，每段确认 Success。
*/

/* ---------- 第一段：类别列 + 个人设置 ---------- */
alter table studios add column if not exists category text not null default '综合';
alter table contests add column if not exists category text not null default '综合';
alter table profiles add column if not exists settings jsonb not null default '{}';

/* ---------- 第二段：草稿 work_type 加 website ---------- */
do $$
declare cname text;
begin
  select conname into cname from pg_constraint
  where conrelid = 'drafts'::regclass and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%work_type%';
  if cname is not null then
    execute 'alter table drafts drop constraint ' || quote_ident(cname);
  end if;
  alter table drafts add constraint drafts_work_type_check
    check (work_type in ('scratch','python','cpp','website'));
end $$;

/* ---------- 第三段：通知表扩展 + 申请/邀请表 ---------- */
alter table notifications add column if not exists studio_id uuid references studios(id) on delete cascade;
alter table notifications add column if not exists ref_id uuid;

create table if not exists studio_join_requests (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references studios(id) on delete cascade,
  user_id uuid not null,
  message text not null default '',
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz default now(),
  unique(studio_id, user_id)
);
alter table studio_join_requests enable row level security;

create table if not exists studio_invites (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references studios(id) on delete cascade,
  inviter_id uuid not null,
  invitee_id uuid not null,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz default now(),
  unique(studio_id, invitee_id)
);
alter table studio_invites enable row level security;

/* ---------- 第四段：管理员判断函数（security definer，避免 RLS 递归） ---------- */
create or replace function is_studio_manager(p_studio_id uuid, p_user_id uuid)
returns boolean as $$
begin
  return exists (select 1 from studio_members
                 where studio_id = p_studio_id and user_id = p_user_id
                 and role in ('owner','vice','admin'));
end; $$ language plpgsql security definer;

drop policy if exists "joinreq 本人可看" on studio_join_requests;
create policy "joinreq 本人可看" on studio_join_requests
  for select using (auth.uid() = user_id);
drop policy if exists "joinreq 管理可看" on studio_join_requests;
create policy "joinreq 管理可看" on studio_join_requests
  for select using (is_studio_manager(studio_id, auth.uid()));

drop policy if exists "invite 相关可看" on studio_invites;
create policy "invite 相关可看" on studio_invites
  for select using (
    auth.uid() = invitee_id or auth.uid() = inviter_id
    or is_studio_manager(studio_id, auth.uid())
  );

/* ---------- 补充：create_contest 加类别参数 ---------- */
drop function if exists create_contest(text, text, text, timestamptz, timestamptz, timestamptz, integer, integer, integer);
create or replace function create_contest(
  p_title text, p_desc text, p_cover text,
  p_submit_start timestamptz, p_submit_end timestamptz, p_vote_end timestamptz,
  p_r1 integer, p_r2 integer, p_r3 integer, p_category text default '综合'
)
returns uuid as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean;
  v_total integer;
  v_id uuid;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select coalesce(is_admin, false) into v_is_admin from profiles where id = v_uid;
  v_total := greatest(p_r1, 0) + greatest(p_r2, 0) + greatest(p_r3, 0);
  if not v_is_admin and v_total > 0 then
    update profiles set points = points - v_total where id = v_uid and points >= v_total;
    if not found then raise exception '积分不足，本次赛事需要锁定 % 积分', v_total; end if;
  end if;
  insert into contests (title, description, cover_url, submit_start, submit_end, vote_end,
    created_by, reward_1st, reward_2nd, reward_3rd, reward_locked, category)
  values (p_title, p_desc, p_cover, p_submit_start, p_submit_end, p_vote_end,
    v_uid, greatest(p_r1,0), greatest(p_r2,0), greatest(p_r3,0),
    case when v_is_admin then 0 else v_total end, coalesce(nullif(p_category, ''), '综合'))
  returning id into v_id;
  return v_id;
end; $$ language plpgsql security definer;
grant execute on function create_contest(text, text, text, timestamptz, timestamptz, timestamptz, integer, integer, integer, text) to authenticated;

/* ---------- 第五段：申请 / 审批 RPC ---------- */
create or replace function request_join_studio(p_studio_id uuid, p_message text)
returns uuid as $$
declare
  v_uid uuid := auth.uid();
  v_req_id uuid;
  v_mgr record;
begin
  if v_uid is null then raise exception '请先登录'; end if;
  if exists (select 1 from studio_members where studio_id = p_studio_id and user_id = v_uid) then
    raise exception '你已经是该工作室成员';
  end if;
  insert into studio_join_requests (studio_id, user_id, message, status)
  values (p_studio_id, v_uid, coalesce(p_message, ''), 'pending')
  on conflict (studio_id, user_id)
  do update set message = excluded.message, status = 'pending', created_at = now()
  returning id into v_req_id;
  for v_mgr in select user_id from studio_members
               where studio_id = p_studio_id and role in ('owner','vice','admin') loop
    if v_mgr.user_id <> v_uid then
      insert into notifications (user_id, from_user_id, type, studio_id, ref_id)
      values (v_mgr.user_id, v_uid, 'studio_request', p_studio_id, v_req_id);
    end if;
  end loop;
  return v_req_id;
end; $$ language plpgsql security definer;

create or replace function handle_join_request(p_request_id uuid, p_approve boolean)
returns text as $$
declare
  v_uid uuid := auth.uid();
  v_req studio_join_requests%rowtype;
begin
  if v_uid is null then raise exception '请先登录'; end if;
  select * into v_req from studio_join_requests where id = p_request_id;
  if not found then raise exception '申请不存在'; end if;
  if v_req.status <> 'pending' then raise exception '该申请已处理'; end if;
  if not is_studio_manager(v_req.studio_id, v_uid) then
    raise exception '只有工作室管理人员可以审批';
  end if;
  if p_approve then
    begin
      insert into studio_members (studio_id, user_id, role)
      values (v_req.studio_id, v_req.user_id, 'member');
    exception when others then
      update studio_join_requests set status = 'rejected' where id = p_request_id;
      insert into notifications (user_id, from_user_id, type, studio_id, ref_id)
      values (v_req.user_id, v_uid, 'studio_request_result', v_req.studio_id, p_request_id);
      return 'rejected:' || SQLERRM;
    end;
    update studio_join_requests set status = 'approved' where id = p_request_id;
  else
    update studio_join_requests set status = 'rejected' where id = p_request_id;
  end if;
  insert into notifications (user_id, from_user_id, type, studio_id, ref_id)
  values (v_req.user_id, v_uid, 'studio_request_result', v_req.studio_id, p_request_id);
  return case when p_approve then 'approved' else 'rejected' end;
end; $$ language plpgsql security definer;

/* ---------- 第六段：邀请 / 接受邀请 RPC ---------- */
create or replace function invite_to_studio(p_studio_id uuid, p_invitee_id uuid)
returns uuid as $$
declare
  v_uid uuid := auth.uid();
  v_inv_id uuid;
begin
  if v_uid is null then raise exception '请先登录'; end if;
  if not is_studio_manager(p_studio_id, v_uid) then
    raise exception '只有工作室管理人员可以邀请';
  end if;
  if exists (select 1 from studio_members where studio_id = p_studio_id and user_id = p_invitee_id) then
    raise exception '对方已经是成员';
  end if;
  insert into studio_invites (studio_id, inviter_id, invitee_id, status)
  values (p_studio_id, v_uid, p_invitee_id, 'pending')
  on conflict (studio_id, invitee_id)
  do update set status = 'pending', inviter_id = excluded.inviter_id, created_at = now()
  returning id into v_inv_id;
  insert into notifications (user_id, from_user_id, type, studio_id, ref_id)
  values (p_invitee_id, v_uid, 'studio_invite', p_studio_id, v_inv_id);
  return v_inv_id;
end; $$ language plpgsql security definer;

create or replace function handle_studio_invite(p_invite_id uuid, p_accept boolean)
returns text as $$
declare
  v_uid uuid := auth.uid();
  v_inv studio_invites%rowtype;
begin
  if v_uid is null then raise exception '请先登录'; end if;
  select * into v_inv from studio_invites where id = p_invite_id;
  if not found then raise exception '邀请不存在'; end if;
  if v_inv.invitee_id <> v_uid then raise exception '这不是给你的邀请'; end if;
  if v_inv.status <> 'pending' then raise exception '该邀请已处理'; end if;
  if p_accept then
    begin
      insert into studio_members (studio_id, user_id, role)
      values (v_inv.studio_id, v_uid, 'member');
    exception when others then
      update studio_invites set status = 'rejected' where id = p_invite_id;
      return 'rejected:' || SQLERRM;
    end;
    update studio_invites set status = 'accepted' where id = p_invite_id;
    insert into notifications (user_id, from_user_id, type, studio_id, ref_id)
    values (v_inv.inviter_id, v_uid, 'studio_invite_result', v_inv.studio_id, p_invite_id);
    return 'accepted';
  else
    update studio_invites set status = 'rejected' where id = p_invite_id;
    return 'rejected';
  end if;
end; $$ language plpgsql security definer;

grant execute on function is_studio_manager(uuid, uuid) to authenticated;
grant execute on function request_join_studio(uuid, text) to authenticated;
grant execute on function handle_join_request(uuid, boolean) to authenticated;
grant execute on function invite_to_studio(uuid, uuid) to authenticated;
grant execute on function handle_studio_invite(uuid, boolean) to authenticated;
