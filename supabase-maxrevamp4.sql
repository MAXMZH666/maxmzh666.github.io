/* ===== MAX社区第四轮改版 supabase-maxrevamp4.sql =====
   站长（profiles.is_admin）在任何工作室都拥有管理权。
   分段执行，每段确认 Success。
*/

/* ---------- 第一段：站长判断函数 ---------- */
create or replace function is_site_admin()
returns boolean as $$
begin
  return exists (select 1 from profiles where id = auth.uid() and coalesce(is_admin, false) = true);
end; $$ language plpgsql security definer;
grant execute on function is_site_admin() to authenticated;

/* ---------- 第二段：成员/职位/移除 ---------- */
drop policy if exists "members 职位可改" on studio_members;
create policy "members 职位可改" on studio_members for update using (
  is_site_admin() or
  exists (select 1 from studio_members m where m.studio_id = studio_members.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'vice'))
) with check (
  is_site_admin() or
  exists (select 1 from studio_members m where m.studio_id = studio_members.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'vice'))
);
drop policy if exists "members 可退出或被管理" on studio_members;
create policy "members 可退出或被管理" on studio_members for delete using (
  auth.uid() = user_id or is_site_admin() or
  exists (select 1 from studio_members m where m.studio_id = studio_members.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);

/* ---------- 第三段：工作室信息/公告/作品 ---------- */
drop policy if exists "studios 管理可改" on studios;
create policy "studios 管理可改" on studios for update using (
  auth.uid() = owner_id or is_site_admin() or
  exists (select 1 from studio_members m where m.studio_id = studios.id and m.user_id = auth.uid() and m.role in ('vice', 'admin'))
);
drop policy if exists "announce 管理可发" on studio_announcements;
create policy "announce 管理可发" on studio_announcements for insert with check (
  is_site_admin() or
  exists (select 1 from studio_members m where m.studio_id = studio_announcements.studio_id
    and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);
drop policy if exists "announce 管理可删" on studio_announcements;
create policy "announce 管理可删" on studio_announcements for delete using (
  is_site_admin() or
  exists (select 1 from studio_members m where m.studio_id = studio_announcements.studio_id
    and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);
drop policy if exists "studio_works 可移除" on studio_works;
create policy "studio_works 可移除" on studio_works for delete using (
  auth.uid() = added_by or is_site_admin() or
  exists (select 1 from studio_members m where m.studio_id = studio_works.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);

/* ---------- 第四段：申请/邀请可见 ---------- */
drop policy if exists "joinreq 管理可看" on studio_join_requests;
create policy "joinreq 管理可看" on studio_join_requests
  for select using (is_site_admin() or is_studio_manager(studio_id, auth.uid()));
drop policy if exists "invite 相关可看" on studio_invites;
create policy "invite 相关可看" on studio_invites
  for select using (
    auth.uid() = invitee_id or auth.uid() = inviter_id
    or is_site_admin() or is_studio_manager(studio_id, auth.uid())
  );

/* ---------- 第五段：审批/邀请 RPC 也允许站长 ---------- */
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
  if not (is_studio_manager(v_req.studio_id, v_uid) or is_site_admin()) then
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

create or replace function invite_to_studio(p_studio_id uuid, p_invitee_id uuid)
returns uuid as $$
declare
  v_uid uuid := auth.uid();
  v_inv_id uuid;
begin
  if v_uid is null then raise exception '请先登录'; end if;
  if not (is_studio_manager(p_studio_id, v_uid) or is_site_admin()) then
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
