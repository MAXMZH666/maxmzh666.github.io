-- MAX社区 站点公告表
create table if not exists site_announcements (
    id uuid primary key default gen_random_uuid(),
    title text not null,
    content text not null default '',
    link_url text,
    is_active boolean not null default true,
    created_at timestamptz not null default now()
);
create index if not exists idx_site_announce_active on site_announcements (is_active, created_at desc);
alter table site_announcements enable row level security;
drop policy if exists "站点公告公开可读" on site_announcements;
create policy "站点公告公开可读" on site_announcements for select using (true);
drop policy if exists "站点公告仅站长可写" on site_announcements;
create policy "站点公告仅站长可写" on site_announcements for all
using (exists (select 1 from profiles where id = auth.uid() and is_admin = true))
with check (exists (select 1 from profiles where id = auth.uid() and is_admin = true));

-- 默认公告
insert into site_announcements (title, content, link_url)
values ('🎉 MAX社区正式上线', '分享你的 Scratch、Python、C++ 作品，在线试玩、评论点赞，结识同好！', 'community-publish.html')
on conflict do nothing;
