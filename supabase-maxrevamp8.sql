/* ===== supabase-maxrevamp8.sql =====
   讨论室分类 + 私信消息类型（图片）。
*/
alter table studio_discussions add column if not exists category text not null default '综合';
create index if not exists idx_sd_cat on studio_discussions (studio_id, category, created_at desc);

alter table direct_messages add column if not exists msg_type text not null default 'text';
drop policy if exists "dm 发送者可删" on direct_messages;
create policy "dm 发送者可删" on direct_messages
  for delete using (auth.uid() = sender_id);
