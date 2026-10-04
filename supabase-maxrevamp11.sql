-- 赛事通知：参赛通知 + 获奖通知

-- 1. 参赛时通知赛事创建者
create or replace function notify_contest_entry() returns trigger as $$
declare
    v_creator uuid;
    v_title text;
begin
    select created_by, title into v_creator, v_title from contests where id = new.contest_id;
    if v_creator is not null and v_creator != new.user_id then
        insert into notifications (user_id, from_user_id, type, ref_id, work_id, content)
        values (v_creator, new.user_id, 'contest_entry', new.contest_id, new.work_id, v_title);
    end if;
    return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_notify_contest_entry on contest_entries;
create trigger trg_notify_contest_entry
after insert on contest_entries
for each row execute function notify_contest_entry();

-- 2. 结算时通知获奖者（修改 settle_contest）
create or replace function settle_contest(p_contest_id uuid)
returns boolean as $$
declare
  v_uid uuid := auth.uid();
  v_creator uuid;
  v_is_admin boolean;
  v_title text;
  r record;
  v_rank int := 0;
  v_bonus int;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select created_by, title into v_creator, v_title from contests where id = p_contest_id;
  if v_creator is null then raise exception 'contest not found'; end if;
  select coalesce(is_admin, false) into v_is_admin from profiles where id = v_uid;
  if v_creator != v_uid and not v_is_admin then raise exception 'not allowed'; end if;
  if (select settled from contests where id = p_contest_id) then raise exception 'already settled'; end if;

  for r in
    select e.user_id, count(v.id) as votes
    from contest_entries e
    left join contest_votes v on v.entry_id = e.id
    where e.contest_id = p_contest_id
    group by e.user_id
    order by votes desc
    limit 3
  loop
    v_rank := v_rank + 1;
    v_bonus := case v_rank when 1 then 100 when 2 then 50 else 30 end;
    update profiles set points = points + v_bonus where id = r.user_id;
    -- 获奖通知
    insert into notifications (user_id, type, ref_id, content)
    values (r.user_id, 'contest_reward', p_contest_id,
            '你在赛事「' || v_title || '」中获得第' || v_rank || '名，奖励 +' || v_bonus || ' 积分');
  end loop;

  update contests set settled = true where id = p_contest_id;
  return true;
end;
$$ language plpgsql security definer;

-- 3. 源码保护：仅授权用户可通过 RPC 获取源码
create or replace function get_work_code(p_work_id uuid)
returns json as $$
declare
    v_code text;
    v_sb3 text;
    v_open boolean;
    v_author uuid;
    v_uid uuid := auth.uid();
    v_admin boolean;
begin
    select code, sb3_url, is_open_source, author_id
    into v_code, v_sb3, v_open, v_author
    from works where id = p_work_id;
    if not found then raise exception 'work not found'; end if;

    select coalesce(is_admin, false) into v_admin from profiles where id = v_uid;

    -- 授权：开源 / 作者 / 站长
    if v_open or v_author = v_uid or v_admin then
        return json_build_object('code', v_code, 'sb3_url', v_sb3);
    else
        raise exception 'not authorized';
    end if;
end;
$$ language plpgsql security definer;

-- 4. 版本历史：仅开源作品公开可见，闭源仅作者/站长
drop policy if exists "versions 公开可读" on work_versions;
create policy "versions 按开源状态可读" on work_versions
for select using (
    exists (select 1 from works w where w.id = work_versions.work_id and w.is_open_source = true)
    or author_id = auth.uid()
    or exists (select 1 from profiles p where p.id = auth.uid() and p.is_admin = true)
);
