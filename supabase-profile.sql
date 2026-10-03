/* 个人信息修改 v1（2026-10-03）
 * 执行方式：Supabase Dashboard → SQL Editor，粘贴执行（很短，一次即可）
 */
alter table profiles add column if not exists avatar_url text not null default '';
alter table profiles add column if not exists bio text not null default '';
