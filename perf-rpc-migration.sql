-- 性能优化：经验/积分/签到合并为单次 RPC（原来每个动作要 3~6 次接口往返）
create or replace function award_exp(p_delta int, p_reason text, p_ref text)
returns int language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_exp int;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  if p_ref is not null and exists (select 1 from exp_log where user_id = v_uid and ref = p_ref) then
    select exp into v_exp from profiles where id = v_uid;
    return v_exp;
  end if;
  update profiles set exp = exp + p_delta where id = v_uid returning exp into v_exp;
  insert into exp_log (user_id, delta, reason, ref)
  values (v_uid, p_delta, coalesce(p_reason, '经验变动'), p_ref);
  return v_exp;
end $$;
grant execute on function award_exp(int, text, text) to authenticated;

create or replace function add_points(p_delta int)
returns int language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_pts int;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  update profiles set points = points + p_delta where id = v_uid returning points into v_pts;
  return v_pts;
end $$;
grant execute on function add_points(int) to authenticated;

create or replace function do_checkin()
returns json language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Shanghai')::date;
  v_streak int := 0;
  v_bonus int := 5;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  if not exists (select 1 from checkins where user_id = v_uid and check_date = v_today) then
    insert into checkins (user_id, check_date, points_awarded) values (v_uid, v_today, 5);
    with recursive s(d) as (
      select v_today
      union all
      select d - 1 from s
      where exists (select 1 from checkins c where c.user_id = v_uid and c.check_date = d - 1)
    )
    select count(*) into v_streak from s;
    if v_streak = 7 then v_bonus := 15;
    elsif v_streak = 30 then v_bonus := 35;
    end if;
    update profiles set points = points + v_bonus, exp = exp + 5 where id = v_uid;
    insert into exp_log (user_id, delta, reason, ref)
    values (v_uid, 5, '每日签到', 'checkin:' || v_today::text);
    return json_build_object('already', false, 'streak', v_streak, 'points', v_bonus);
  end if;
  with recursive s(d) as (
    select v_today
    union all
    select d - 1 from s
    where exists (select 1 from checkins c where c.user_id = v_uid and c.check_date = d - 1)
  )
  select count(*) into v_streak from s;
  return json_build_object('already', true, 'streak', v_streak);
end $$;
grant execute on function do_checkin() to authenticated;
