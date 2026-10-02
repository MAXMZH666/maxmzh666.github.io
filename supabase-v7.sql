-- ============================================================
-- MAXMZH 游戏社区 v7：Windows / Linux 作品类型 + 安装包存储桶
-- 在 Supabase 后台 SQL Editor 里完整执行一次即可（可重复执行）
-- ============================================================

-- 1. work_type 增加 windows / linux（先删掉旧的检查约束再重建）
DO $$ DECLARE cname text; BEGIN
  SELECT conname INTO cname FROM pg_constraint
  WHERE conrelid = 'works'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%work_type%';
  IF cname IS NOT NULL THEN
    EXECUTE 'alter table works drop constraint ' || quote_ident(cname);
  END IF;
END $$;

ALTER TABLE works DROP CONSTRAINT IF EXISTS works_work_type_check;
alter table works add constraint works_work_type_check
  check (work_type in ('scratch','python','cpp','apk','windows','linux'));

-- 2. appfiles 公开桶：存放 Windows / Linux 安装包（apk_url 字段复用为安装包地址）
insert into storage.buckets (id, name, public)
values ('appfiles', 'appfiles', true)
on conflict (id) do nothing;

drop policy if exists "appfiles 公开读" on storage.objects;
create policy "appfiles 公开读" on storage.objects
  for select using (bucket_id = 'appfiles');

drop policy if exists "appfiles 登录可传" on storage.objects;
create policy "appfiles 登录可传" on storage.objects
  for insert with check (bucket_id = 'appfiles' and auth.role() = 'authenticated');

drop policy if exists "appfiles 登录可删" on storage.objects;
create policy "appfiles 登录可删" on storage.objects
  for delete using (bucket_id = 'appfiles' and auth.role() = 'authenticated');
