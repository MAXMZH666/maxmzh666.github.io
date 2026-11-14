-- 成长体系迁移：经验值 + 经验记录（每日签到表 checkins 已存在，本次复用不重建）
-- 规则：经验发放走 profiles.exp（读-改-写，与积分同一模式）；exp_log 记录明细，ref 做防重复键

-- 1. profiles 加经验列
alter table profiles add column if not exists exp int not null default 0;

-- 2. 经验记录表
create table if not exists exp_log (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references profiles(id) on delete cascade,
    delta int not null,
    reason text not null default '经验变动',
    ref text,
    created_at timestamptz not null default now()
);
create index if not exists idx_exp_log_user on exp_log(user_id, created_at desc);
create unique index if not exists uq_exp_log_ref on exp_log(user_id, ref) where ref is not null;

grant select, insert on exp_log to authenticated;
alter table exp_log enable row level security;
drop policy if exists "经验记录自己可见" on exp_log;
create policy "经验记录自己可见" on exp_log for select using (auth.uid() = user_id);
drop policy if exists "经验记录自己可写" on exp_log;
create policy "经验记录自己可写" on exp_log for insert with check (auth.uid() = user_id);

-- 3. 存量回填：发帖*10 + 回帖*3 + 作品*15 + 论坛获赞*2 + 签到*5
update profiles p set exp = sub.total
from (
    select pr.id,
        (select count(*) from forum_threads t where t.author_id = pr.id) * 10
        + (select count(*) from forum_posts po where po.author_id = pr.id) * 3
        + (select count(*) from works w where w.author_id = pr.id) * 15
        + (select count(*) from forum_post_likes l join forum_posts po2 on po2.id = l.post_id where po2.author_id = pr.id) * 2
        + (select count(*) from checkins c where c.user_id = pr.id) * 5 as total
    from profiles pr
) sub
where p.id = sub.id and sub.total > 0;

-- 4. 回填记一条汇总经验记录（ref=backfill 防重复执行）
insert into exp_log (user_id, delta, reason, ref)
select id, exp, '历史活跃折算', 'backfill' from profiles where exp > 0
on conflict do nothing;
