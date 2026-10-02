-- ============================================================
-- MAXMZH 游戏社区 v5：多类型作品（Scratch/Python/C++/APK）+ 排行榜
-- 在 Supabase 后台 SQL Editor 里完整执行一次即可（可重复执行）
-- ============================================================

-- 1. works 表新增字段
alter table works add column if not exists work_type text not null default 'scratch';
alter table works add column if not exists code text;
alter table works add column if not exists apk_url text;
alter table works add column if not exists screenshots text[] not null default '{}';

-- 类型取值约束
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'works_work_type_check') then
    alter table works add constraint works_work_type_check
      check (work_type in ('scratch', 'python', 'cpp', 'apk'));
  end if;
end $$;

-- 2. APK 存储桶（公开读）
insert into storage.buckets (id, name, public)
values ('apks', 'apks', true)
on conflict (id) do nothing;

-- 3. apks bucket 的 RLS 策略：公开读，登录用户可上传/更新/删除
drop policy if exists "apks 公开读取" on storage.objects;
create policy "apks 公开读取" on storage.objects
  for select using (bucket_id = 'apks');

drop policy if exists "apks 登录可上传" on storage.objects;
create policy "apks 登录可上传" on storage.objects
  for insert with check (bucket_id = 'apks' and auth.role() = 'authenticated');

drop policy if exists "apks 登录可更新" on storage.objects;
create policy "apks 登录可更新" on storage.objects
  for update using (bucket_id = 'apks' and auth.role() = 'authenticated');

drop policy if exists "apks 登录可删除" on storage.objects;
create policy "apks 登录可删除" on storage.objects
  for delete using (bucket_id = 'apks' and auth.role() = 'authenticated');
