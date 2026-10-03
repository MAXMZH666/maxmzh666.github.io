/* ===== MAX社区 supabase-maxrevamp6.sql =====
   评论作者可删 + 工作室室长可解散。
   一段执行，确认 Success。
*/

/* 评论：作者本人可删（管理员可删已存在） */
drop policy if exists "comments 作者可删" on comments;
create policy "comments 作者可删" on comments
  for delete using (
    auth.uid() = author_id or is_site_admin()
  );

/* 工作室：室长可解散（级联删除成员/公告/作品关联/申请/邀请/讨论/通知） */
drop policy if exists "studios 室长可删" on studios;
create policy "studios 室长可删" on studios
  for delete using (
    auth.uid() = owner_id or is_site_admin()
  );
