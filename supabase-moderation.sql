-- 社区第八期：社区共建（被举报作品公示 + 全民投票裁决）
-- 在 Supabase SQL Editor 中执行

-- 1. 举报案件表（公开）
create table if not exists report_cases (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references works(id) on delete cascade,
  reason text not null default '',
  report_count int not null default 1,
  status text not null default 'voting' check (status in ('voting', 'closed')),
  verdict text check (verdict in ('keep', 'remove')),
  created_at timestamptz default now(),
  closed_at timestamptz,
  unique(work_id)
);
create index if not exists idx_report_cases_status on report_cases(status);

-- 2. 裁决投票表（每人每案件限投 1 票）
create table if not exists report_votes (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references report_cases(id) on delete cascade,
  voter_id uuid not null references profiles(id) on delete cascade,
  verdict text not null check (verdict in ('keep', 'remove')),
  created_at timestamptz default now(),
  unique(case_id, voter_id)
);
create index if not exists idx_report_votes_case on report_votes(case_id);

-- 3. RLS
alter table report_cases enable row level security;
alter table report_votes enable row level security;

drop policy if exists "cases 公开可读" on report_cases;
create policy "cases 公开可读" on report_cases for select using (true);
drop policy if exists "cases 管理员可改" on report_cases;
create policy "cases 管理员可改" on report_cases for update using (
  exists (select 1 from profiles where id = auth.uid() and is_admin = true)
);

drop policy if exists "case_votes 公开可读" on report_votes;
create policy "case_votes 公开可读" on report_votes for select using (true);
drop policy if exists "case_votes 登录可投票" on report_votes;
create policy "case_votes 登录可投票" on report_votes for insert with check (auth.uid() = voter_id);

-- 4. 举报自动建案触发器（作品被举报时自动创建公示案件）
create or replace function create_report_case()
returns trigger as $$
begin
  if NEW.target_type = 'work' then
    insert into report_cases (work_id, reason, report_count)
    values (NEW.target_id::uuid, NEW.reason, 1)
    on conflict (work_id) do update set
      report_count = report_cases.report_count + 1,
      reason = report_cases.reason || '；' || NEW.reason,
      status = 'voting',
      verdict = null,
      closed_at = null;
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_create_report_case on reports;
create trigger trg_create_report_case
after insert on reports
for each row
execute function create_report_case();

-- 5. 管理员执行裁决函数
create or replace function execute_report_verdict(p_case_id uuid, p_verdict text)
returns boolean as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean;
  v_work_id uuid;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  if p_verdict not in ('keep', 'remove') then raise exception 'bad verdict'; end if;
  select coalesce(is_admin, false) into v_is_admin from profiles where id = v_uid;
  if not v_is_admin then raise exception 'not allowed'; end if;

  select work_id into v_work_id from report_cases where id = p_case_id;
  if v_work_id is null then raise exception 'case not found'; end if;

  if p_verdict = 'remove' then
    delete from works where id = v_work_id;
  end if;

  update report_cases
  set status = 'closed', verdict = p_verdict, closed_at = now()
  where id = p_case_id;
  return true;
end;
$$ language plpgsql security definer;
