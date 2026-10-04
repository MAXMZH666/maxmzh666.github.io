-- 修复 chat_group_members RLS 无限递归
-- 原理：策略中直接子查询 chat_group_members 会触发自身 SELECT 策略，形成递归
-- 解法：用 SECURITY DEFINER 函数（绕过 RLS）做成员判断

create or replace function is_group_member(p_group_id uuid)
returns boolean as $$
begin
    return exists (
        select 1 from chat_group_members
        where group_id = p_group_id and user_id = auth.uid()
    );
end;
$$ language plpgsql security definer;

-- 重写成员表 SELECT 策略：用函数代替自引用子查询
drop policy if exists "群成员列表成员可见" on chat_group_members;
create policy "群成员列表成员可见" on chat_group_members for select using (
    is_group_member(chat_group_members.group_id)
);

-- 重写群表 SELECT 策略：用函数代替子查询
drop policy if exists "群成员可读群" on chat_groups;
create policy "群成员可读群" on chat_groups for select using (
    auth.uid() = owner_id or is_group_member(chat_groups.id)
);

-- 重写拉人策略：用函数检查群主身份（避免通过 chat_groups SELECT 间接递归）
drop policy if exists "群主可拉人" on chat_group_members;
create policy "群主可拉人" on chat_group_members for insert with check (
    exists (
        select 1 from chat_groups
        where id = chat_group_members.group_id and owner_id = auth.uid()
    )
);
