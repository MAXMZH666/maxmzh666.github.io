-- 群聊 RLS 修复：群主可看自己的群
drop policy if exists "群成员可读群" on chat_groups;
create policy "群成员可读群" on chat_groups for select using (
    auth.uid() = owner_id
    or exists (select 1 from chat_group_members where group_id = chat_groups.id and user_id = auth.uid())
);
