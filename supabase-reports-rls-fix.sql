-- reports 表 RLS 修复（2026-11-15）
-- 背景：前端所有举报（作品/评论/赛事/回帖）插入 reports 均报
-- "new row violates row-level security policy"——表上只有管理员 SELECT 策略，
-- 缺登录用户 INSERT 策略。本迁移补齐：登录可举报（只能以本人名义）、
-- 本人可读/删自己提交的举报、管理员可删任意举报。幂等，可重复执行。
alter table public.reports enable row level security;

drop policy if exists "reports 登录可举报" on public.reports;
create policy "reports 登录可举报" on public.reports
  for insert to authenticated with check (auth.uid() = reporter_id);

drop policy if exists "reports 本人可读自己的" on public.reports;
create policy "reports 本人可读自己的" on public.reports
  for select to authenticated using (auth.uid() = reporter_id);

drop policy if exists "reports 本人可删自己的" on public.reports;
create policy "reports 本人可删自己的" on public.reports
  for delete to authenticated using (auth.uid() = reporter_id);

drop policy if exists "reports 管理员可删" on public.reports;
create policy "reports 管理员可删" on public.reports
  for delete using (
    exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.is_admin = true)
  );
