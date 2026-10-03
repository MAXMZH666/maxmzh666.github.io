-- MAX社区第二轮改版 SQL 迁移
-- 在 Supabase SQL Editor 中分段执行

-- ===== 1. 修复一人一工作室触发器（拆分为两个独立函数） =====
drop trigger if exists trg_one_studio_create on studios;
drop trigger if exists trg_one_studio_join on studio_members;
drop function if exists check_one_studio_per_user();

create or replace function check_studio_create()
returns trigger as $$
declare
  v_other uuid;
begin
  select id into v_other from studios where owner_id = NEW.owner_id and id != NEW.id limit 1;
  if v_other is not null then raise exception '每人只能创建一个工作室'; end if;
  select studio_id into v_other from studio_members where user_id = NEW.owner_id and studio_id != NEW.id limit 1;
  if v_other is not null then raise exception '你已加入一个工作室，不能再创建'; end if;
  return NEW;
end;
$$ language plpgsql security definer;

create or replace function check_studio_join()
returns trigger as $$
declare
  v_other uuid;
begin
  select studio_id into v_other from studio_members where user_id = NEW.user_id and studio_id != NEW.studio_id limit 1;
  if v_other is not null then raise exception '每人只能加入一个工作室'; end if;
  select id into v_other from studios where owner_id = NEW.user_id and id != NEW.studio_id limit 1;
  if v_other is not null then raise exception '你已创建工作室，不能再加入别的'; end if;
  return NEW;
end;
$$ language plpgsql security definer;

create trigger trg_one_studio_create
before insert on studios for each row execute function check_studio_create();

create trigger trg_one_studio_join
before insert on studio_members for each row execute function check_studio_join();

-- ===== 2. 赛事自定义奖励 =====
alter table contests add column if not exists reward_1st integer not null default 100;
alter table contests add column if not exists reward_2nd integer not null default 50;
alter table contests add column if not exists reward_3rd integer not null default 30;
alter table contests add column if not exists reward_locked integer not null default 0;

-- 创建赛事（含奖励锁定：非管理员从积分扣除）
create or replace function create_contest(
  p_title text, p_desc text, p_cover text,
  p_submit_start timestamptz, p_submit_end timestamptz, p_vote_end timestamptz,
  p_r1 integer, p_r2 integer, p_r3 integer
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
    created_by, reward_1st, reward_2nd, reward_3rd, reward_locked)
  values (p_title, p_desc, p_cover, p_submit_start, p_submit_end, p_vote_end,
    v_uid, greatest(p_r1,0), greatest(p_r2,0), greatest(p_r3,0),
    case when v_is_admin then 0 else v_total end)
  returning id into v_id;
  return v_id;
end;
$$ language plpgsql security definer;

-- 结算：按自定义奖励发放；未发完的锁定积分退回创建者
create or replace function settle_contest(p_contest_id uuid)
returns boolean as $$
declare
  v_uid uuid := auth.uid();
  v_creator uuid;
  v_is_admin boolean;
  v_r1 integer; v_r2 integer; v_r3 integer; v_locked integer;
  r record;
  v_rank integer := 0;
  v_bonus integer;
  v_paid integer := 0;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select created_by, reward_1st, reward_2nd, reward_3rd, reward_locked
    into v_creator, v_r1, v_r2, v_r3, v_locked
    from contests where id = p_contest_id;
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
    v_bonus := case v_rank when 1 then v_r1 when 2 then v_r2 else v_r3 end;
    if v_bonus > 0 then
      update profiles set points = points + v_bonus where id = r.user_id;
      v_paid := v_paid + v_bonus;
    end if;
  end loop;

  -- 退回未发完的锁定积分
  if v_locked > v_paid then
    update profiles set points = points + (v_locked - v_paid) where id = v_creator;
  end if;

  update contests set settled = true, reward_locked = 0 where id = p_contest_id;
  return true;
end;
$$ language plpgsql security definer;

-- 删除未结算赛事时退回锁定积分
create or replace function refund_contest_on_delete()
returns trigger as $$
begin
  if OLD.reward_locked > 0 and not OLD.settled then
    update profiles set points = points + OLD.reward_locked where id = OLD.created_by;
  end if;
  return OLD;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_refund_contest on contests;
create trigger trg_refund_contest
before delete on contests for each row execute function refund_contest_on_delete();

-- ===== 3. 工作室职位体系：市长/副市长/管理员(3)/成员 =====
alter table studio_members drop constraint if exists studio_members_role_check;
alter table studio_members add constraint studio_members_role_check
  check (role in ('owner', 'vice', 'admin', 'member'));

-- 更新 RLS 中的角色判断（含 vice）
-- （原有策略用 role in ('owner','admin')，需要加入 'vice'）

-- 工作室公告表
create table if not exists studio_announcements (
  id uuid primary key default gen_random_uuid(),
  studio_id uuid not null references studios(id) on delete cascade,
  author_id uuid not null references profiles(id) on delete cascade,
  content text not null,
  created_at timestamptz default now()
);
create index if not exists idx_announce_studio on studio_announcements(studio_id);
alter table studio_announcements enable row level security;
drop policy if exists "announce 公开可读" on studio_announcements;
create policy "announce 公开可读" on studio_announcements for select using (true);
drop policy if exists "announce 管理可发" on studio_announcements;
create policy "announce 管理可发" on studio_announcements for insert with check (
  exists (select 1 from studio_members m where m.studio_id = studio_announcements.studio_id
    and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);
drop policy if exists "announce 管理可删" on studio_announcements;
create policy "announce 管理可删" on studio_announcements for delete using (
  exists (select 1 from studio_members m where m.studio_id = studio_announcements.studio_id
    and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);

-- ===== 4. 工作室 RLS：vice 加入管理角色；允许改职位 =====
drop policy if exists "members 可加入" on studio_members;
create policy "members 可加入" on studio_members for insert with check (
  auth.uid() = user_id or
  exists (select 1 from studio_members m where m.studio_id = studio_members.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);
drop policy if exists "members 可退出或被管理" on studio_members;
create policy "members 可退出或被管理" on studio_members for delete using (
  auth.uid() = user_id or
  exists (select 1 from studio_members m where m.studio_id = studio_members.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);
drop policy if exists "members 职位可改" on studio_members;
create policy "members 职位可改" on studio_members for update using (
  exists (select 1 from studio_members m where m.studio_id = studio_members.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'vice'))
) with check (
  exists (select 1 from studio_members m where m.studio_id = studio_members.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'vice'))
);
drop policy if exists "studio_works 可移除" on studio_works;
create policy "studio_works 可移除" on studio_works for delete using (
  auth.uid() = added_by or
  exists (select 1 from studio_members m where m.studio_id = studio_works.studio_id and m.user_id = auth.uid() and m.role in ('owner', 'vice', 'admin'))
);
-- 工作室信息修改：市长/副市长/管理员
drop policy if exists "studios 管理可改" on studios;
create policy "studios 管理可改" on studios for update using (
  auth.uid() = owner_id or
  exists (select 1 from studio_members m where m.studio_id = studios.id and m.user_id = auth.uid() and m.role in ('vice', 'admin'))
);
