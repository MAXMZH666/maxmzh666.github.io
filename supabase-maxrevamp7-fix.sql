/* ===== supabase-maxrevamp7-fix.sql =====
   修复 maxrevamp7 中两个函数的列名：notifications 表用 from_user_id，不是 actor_id。
*/

create or replace function notify_dm() returns trigger as $$
begin
  insert into notifications (user_id, type, from_user_id, content, ref_id)
  values (new.receiver_id, 'dm', new.sender_id, '发来一条私信', new.id);
  return new;
exception when others then
  return new;
end;
$$ language plpgsql security definer;

create or replace function send_mention(p_user_id uuid, p_actor_id uuid, p_content text, p_ref_id uuid, p_ref_type text)
returns void as $$
begin
  if p_user_id = p_actor_id then return; end if;
  insert into notifications (user_id, type, from_user_id, content, ref_id)
  values (p_user_id, 'mention', p_actor_id, p_content, p_ref_id);
exception when others then
  null;
end;
$$ language plpgsql security definer;
