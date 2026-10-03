-- 社区第七期：赛事中心
-- 在 Supabase SQL Editor 中执行

-- 1. 赛事表
create table if not exists contests (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text default '',
  cover_url text,
  submit_start timestamptz not null,
  submit_end timestamptz not null,
  vote_end timestamptz not null,
  settled boolean not null default false,
  created_by uuid not null references profiles(id) on delete cascade,
  created_at timestamptz default now()
);
create index if not exists idx_contests_dates on contests(submit_start, submit_end, vote_end);

-- 2. 参赛作品表
create table if not exists contest_entries (
  id uuid primary key default gen_random_uuid(),
  contest_id uuid not null references contests(id) on delete cascade,
  work_id uuid not null references works(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  submitted_at timestamptz default now(),
  unique(contest_id, work_id)
);
create index if not exists idx_entries_contest on contest_entries(contest_id);

-- 3. 投票表（每人每赛事限投 1 票）
create table if not exists contest_votes (
  id uuid primary key default gen_random_uuid(),
  contest_id uuid not null references contests(id) on delete cascade,
  entry_id uuid not null references contest_entries(id) on delete cascade,
  voter_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz default now(),
  unique(contest_id, voter_id)
);
create index if not exists idx_votes_entry on contest_votes(entry_id);
create index if not exists idx_votes_contest on contest_votes(contest_id);

-- 4. RLS
alter table contests enable row level security;
alter table contest_entries enable row level security;
alter table contest_votes enable row level security;

drop policy if exists "contests 公开可读" on contests;
create policy "contests 公开可读" on contests for select using (true);
drop policy if exists "contests 登录可创建" on contests;
create policy "contests 登录可创建" on contests for insert with check (auth.uid() = created_by);
drop policy if exists "contests 作者或管理员可改" on contests;
create policy "contests 作者或管理员可改" on contests for update using (
  auth.uid() = created_by or exists (select 1 from profiles where id = auth.uid() and is_admin = true)
);
drop policy if exists "contests 作者或管理员可删" on contests;
create policy "contests 作者或管理员可删" on contests for delete using (
  auth.uid() = created_by or exists (select 1 from profiles where id = auth.uid() and is_admin = true)
);

drop policy if exists "entries 公开可读" on contest_entries;
create policy "entries 公开可读" on contest_entries for select using (true);
drop policy if exists "entries 登录可投稿" on contest_entries;
create policy "entries 登录可投稿" on contest_entries for insert with check (auth.uid() = user_id);
drop policy if exists "entries 本人可撤回" on contest_entries;
create policy "entries 本人可撤回" on contest_entries for delete using (auth.uid() = user_id);

drop policy if exists "votes 公开可读" on contest_votes;
create policy "votes 公开可读" on contest_votes for select using (true);
drop policy if exists "votes 登录可投票" on contest_votes;
create policy "votes 登录可投票" on contest_votes for insert with check (auth.uid() = voter_id);

-- 5. 结算发奖函数（前三名 +100/+50/+30 积分，仅创建者或管理员可调用）
create or replace function settle_contest(p_contest_id uuid)
returns boolean as $$
declare
  v_uid uuid := auth.uid();
  v_creator uuid;
  v_is_admin boolean;
  r record;
  v_rank int := 0;
  v_bonus int;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select created_by into v_creator from contests where id = p_contest_id;
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
  end loop;

  update contests set settled = true where id = p_contest_id;
  return true;
end;
$$ language plpgsql security definer;
