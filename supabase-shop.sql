-- 社区第六期：积分商城
-- 在 Supabase SQL Editor 中执行

-- 1. 商品表
create table if not exists shop_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text default '',
  price integer not null default 0,
  item_type text not null,   -- frame 头像框 | badge 徽章 | title 称号
  item_data text not null,   -- frame: CSS类名；badge: emoji；title: 称号文字
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz default now()
);

-- 2. 用户物品表
create table if not exists user_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  item_id uuid not null references shop_items(id) on delete cascade,
  is_equipped boolean not null default false,
  purchased_at timestamptz default now(),
  unique(user_id, item_id)
);
create index if not exists idx_user_items_user on user_items(user_id);

-- 3. RLS
alter table shop_items enable row level security;
alter table user_items enable row level security;

drop policy if exists "shop_items 公开可读" on shop_items;
create policy "shop_items 公开可读" on shop_items for select using (true);

drop policy if exists "user_items 本人可读" on user_items;
create policy "user_items 本人可读" on user_items for select using (auth.uid() = user_id);
-- 购买/装备走 SECURITY DEFINER 函数，不开放直接写

-- 4. 购买函数（原子：扣积分+发放）
create or replace function purchase_shop_item(p_item_id uuid)
returns boolean as $$
declare
  v_price integer;
  v_uid uuid := auth.uid();
  v_pts integer;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  select price into v_price from shop_items where id = p_item_id and is_active = true;
  if v_price is null then raise exception 'item not found'; end if;
  select points into v_pts from profiles where id = v_uid;
  if v_pts is null or v_pts < v_price then raise exception 'not enough points'; end if;
  -- 已拥有则直接返回成功，不重复扣费
  if exists (select 1 from user_items where user_id = v_uid and item_id = p_item_id) then
    return true;
  end if;
  update profiles set points = points - v_price where id = v_uid;
  insert into user_items (user_id, item_id) values (v_uid, p_item_id)
  on conflict (user_id, item_id) do nothing;
  return true;
end;
$$ language plpgsql security definer;

-- 5. 装备函数（同类型只能装备一个）
create or replace function equip_shop_item(p_item_id uuid)
returns boolean as $$
declare
  v_uid uuid := auth.uid();
  v_type text;
begin
  if v_uid is null then raise exception 'not logged in'; end if;
  if not exists (select 1 from user_items where user_id = v_uid and item_id = p_item_id) then
    raise exception 'not owned';
  end if;
  select item_type into v_type from shop_items where id = p_item_id;
  update user_items set is_equipped = false
  where user_id = v_uid and item_id in (select id from shop_items where item_type = v_type);
  update user_items set is_equipped = true
  where user_id = v_uid and item_id = p_item_id;
  return true;
end;
$$ language plpgsql security definer;

-- 6. 卸下函数
create or replace function unequip_shop_item(p_item_id uuid)
returns boolean as $$
begin
  update user_items set is_equipped = false
  where user_id = auth.uid() and item_id = p_item_id;
  return true;
end;
$$ language plpgsql security definer;

-- 7. 种子商品
insert into shop_items (name, description, price, item_type, item_data, sort_order) values
-- 头像框
('金色光环', '闪耀的金色边框，彰显尊贵', 100, 'frame', 'frame-gold', 1),
('赛博蓝', '未来感十足的霓虹蓝边框', 150, 'frame', 'frame-cyber', 2),
('彩虹流光', '七彩流转的梦幻边框', 200, 'frame', 'frame-rainbow', 3),
-- 徽章
('社区新星', '新人报道，未来可期', 50, 'badge', '🌟', 11),
('活跃达人', '社区的活跃分子', 100, 'badge', '🔥', 12),
('社区元老', '见证社区成长的元老', 300, 'badge', '👑', 13),
-- 称号
('初心者', '每一个大神都曾是初心者', 30, 'title', '初心者', 21),
('创作者', '用作品说话的人', 80, 'title', '创作者', 22),
('大神', '社区公认的大神', 200, 'title', '大神', 23)
on conflict do nothing;
