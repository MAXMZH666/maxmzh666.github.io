-- MAX社区大改版 SQL 迁移（一次执行）
-- 在 Supabase SQL Editor 中执行

-- 1. 防扒源：作品开源开关
alter table works add column if not exists is_open_source boolean not null default false;

-- 2. 个人主页背景
alter table profiles add column if not exists background_url text;

-- 3. 工作室封面
alter table studios add column if not exists cover_url text;

-- 4. 一人一工作室：创建/加入限制触发器
create or replace function check_one_studio_per_user()
returns trigger as $$
declare
  v_uid uuid;
  v_other uuid;
begin
  if TG_TABLE_NAME = 'studios' then
    v_uid := NEW.owner_id;
    -- 不能已拥有或已加入别的工作室
    select id into v_other from studios where owner_id = v_uid and id != NEW.id limit 1;
    if v_other is not null then raise exception '每人只能创建一个工作室'; end if;
    select studio_id into v_other from studio_members where user_id = v_uid and studio_id != NEW.id limit 1;
    if v_other is not null then raise exception '你已加入一个工作室，不能再创建'; end if;
  elsif TG_TABLE_NAME = 'studio_members' then
    v_uid := NEW.user_id;
    select studio_id into v_other from studio_members where user_id = v_uid and studio_id != NEW.studio_id limit 1;
    if v_other is not null then raise exception '每人只能加入一个工作室'; end if;
    select id into v_other from studios where owner_id = v_uid and id != NEW.studio_id limit 1;
    if v_other is not null then raise exception '你已创建工作室，不能再加入别的'; end if;
  end if;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_one_studio_create on studios;
create trigger trg_one_studio_create
before insert on studios
for each row execute function check_one_studio_per_user();

drop trigger if exists trg_one_studio_join on studio_members;
create trigger trg_one_studio_join
before insert on studio_members
for each row execute function check_one_studio_per_user();

-- 5. 商城新增背景商品（静态渐变免费/低价，动态CSS高价）
-- item_data 存 CSS background 值；animated 前缀表示动态
insert into shop_items (name, description, item_type, price, item_data) values
('晨曦微光', '静态背景：柔和的晨曦渐变', 'background', 0, 'linear-gradient(135deg,#1a1a2e 0%,#16213e 50%,#0f3460 100%)'),
('薄荷清风', '静态背景：清新的薄荷绿渐变', 'background', 30, 'linear-gradient(135deg,#0b3d2e 0%,#0e5e42 60%,#0a2e23 100%)'),
('落日熔金', '静态背景：落日熔金渐变', 'background', 30, 'linear-gradient(135deg,#3d1a0b 0%,#7a2e0e 55%,#2e0f0a 100%)'),
('星云流动', '动态背景：缓缓流动的星云', 'background', 150, 'animated:nebula'),
('极光之舞', '动态背景：梦幻极光', 'background', 200, 'animated:aurora'),
('赛博脉冲', '动态背景：赛博朋克脉冲', 'background', 250, 'animated:cyber');
