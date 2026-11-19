-- ============================================================
-- XJR PRINTING — initial schema
-- ============================================================
create extension if not exists "pgcrypto";

-- ---------- enums ----------
create type public.app_role as enum ('customer','admin');
create type public.order_status as enum (
  'pending','confirmed','processing','printing',
  'ready_for_dispatch','shipped','delivered','cancelled'
);
create type public.design_status as enum ('submitted','approved','rejected','in_production');

-- ---------- profiles ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  whatsapp text,
  default_country text,
  default_state text,
  default_city text,
  default_address text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null default 'customer',
  unique (user_id, role)
);

-- security-definer helper used by every admin policy
create or replace function public.is_admin(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.user_roles where user_id = uid and role = 'admin');
$$;

-- auto-create profile + default customer role on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name) values (new.id, new.raw_user_meta_data->>'full_name');
  insert into public.user_roles (user_id, role) values (new.id, 'customer') on conflict do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

-- updated_at trigger
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
create trigger trg_profiles_updated before update on public.profiles
for each row execute function public.touch_updated_at();

-- ---------- categories ----------
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  image_url text,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz default now()
);

-- ---------- products ----------
create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  description text,
  category_id uuid references public.categories(id) on delete set null,
  price_kobo bigint not null check (price_kobo >= 0),
  sale_price_kobo bigint check (sale_price_kobo is null or sale_price_kobo >= 0),
  sizes text[] not null default '{}',
  colours text[] not null default '{}',
  stock int not null default 0 check (stock >= 0),
  is_active boolean not null default true,
  is_featured boolean not null default false,
  is_new_arrival boolean not null default false,
  is_best_seller boolean not null default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index on public.products (category_id);
create index on public.products (is_active);
create trigger trg_products_updated before update on public.products
for each row execute function public.touch_updated_at();

create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  url text not null,
  sort_order int not null default 0,
  created_at timestamptz default now()
);
create index on public.product_images (product_id);

-- ---------- orders ----------
create sequence public.order_seq start 1001;

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default ('XJR-' || to_char(now(),'YYMM') || '-' || nextval('public.order_seq')),
  user_id uuid references auth.users(id) on delete set null,
  customer_name text not null,
  email text not null,
  phone text not null,
  whatsapp text,
  country text not null,
  state text,
  city text,
  address text not null,
  notes text,
  subtotal_kobo bigint not null default 0,
  delivery_kobo bigint not null default 0,
  total_kobo bigint not null default 0,
  status public.order_status not null default 'pending',
  admin_notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index on public.orders (user_id);
create index on public.orders (status);
create trigger trg_orders_updated before update on public.orders
for each row execute function public.touch_updated_at();

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  size text,
  colour text,
  quantity int not null check (quantity > 0),
  unit_price_kobo bigint not null,
  line_total_kobo bigint not null
);
create index on public.order_items (order_id);

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  status public.order_status not null,
  note text,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz default now()
);
create index on public.order_status_history (order_id);

-- record initial status + every change
create or replace function public.log_order_status() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT') then
    insert into public.order_status_history(order_id, status, changed_by)
    values (new.id, new.status, new.user_id);
  elsif (tg_op = 'UPDATE' and new.status <> old.status) then
    insert into public.order_status_history(order_id, status, changed_by)
    values (new.id, new.status, auth.uid());
  end if;
  return new;
end; $$;
create trigger trg_order_status after insert or update of status on public.orders
for each row execute function public.log_order_status();

-- ---------- design requests ----------
create table public.design_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  customer_name text not null,
  email text not null,
  phone text not null,
  whatsapp text,
  shirt_colour text,
  size text,
  placement text,
  custom_text text,
  instructions text,
  uploaded_artwork_url text,
  ai_prompt text,
  ai_artwork_url text,
  status public.design_status not null default 'submitted',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create trigger trg_designs_updated before update on public.design_requests
for each row execute function public.touch_updated_at();

-- ---------- store settings (single row) ----------
create table public.store_settings (
  id int primary key default 1 check (id = 1),
  store_name text not null default 'XJR PRINTING',
  logo_url text,
  description text,
  whatsapp text not null default '+2347015119367',
  phone text,
  email text,
  address text,
  instagram text,
  facebook text,
  twitter text,
  delivery_info text,
  return_policy text,
  announcement text,
  currency text not null default 'NGN',
  updated_at timestamptz default now()
);
create trigger trg_settings_updated before update on public.store_settings
for each row execute function public.touch_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table public.profiles              enable row level security;
alter table public.user_roles            enable row level security;
alter table public.categories            enable row level security;
alter table public.products              enable row level security;
alter table public.product_images        enable row level security;
alter table public.orders                enable row level security;
alter table public.order_items           enable row level security;
alter table public.order_status_history  enable row level security;
alter table public.design_requests       enable row level security;
alter table public.store_settings        enable row level security;

-- profiles
create policy "profiles self read"   on public.profiles for select using (auth.uid() = id or public.is_admin(auth.uid()));
create policy "profiles self update" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- user_roles: only admins read/write; users can read their own role
create policy "roles read own"    on public.user_roles for select using (user_id = auth.uid() or public.is_admin(auth.uid()));
create policy "roles admin write" on public.user_roles for all    using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- categories: public read active, admin manage
create policy "categories public read" on public.categories for select using (is_active or public.is_admin(auth.uid()));
create policy "categories admin write" on public.categories for all    using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- products: public read active, admin manage
create policy "products public read" on public.products for select using (is_active or public.is_admin(auth.uid()));
create policy "products admin write" on public.products for all    using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

create policy "product_images public read" on public.product_images for select using (true);
create policy "product_images admin write" on public.product_images for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- orders: customer sees own, admin sees all; customer can insert as themselves
create policy "orders owner read"   on public.orders for select using (user_id = auth.uid() or public.is_admin(auth.uid()));
create policy "orders anon insert"  on public.orders for insert with check (true);
create policy "orders admin write"  on public.orders for update using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));
create policy "orders admin delete" on public.orders for delete using (public.is_admin(auth.uid()));

create policy "order_items owner read"  on public.order_items for select using (
  exists(select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin(auth.uid())))
);
create policy "order_items anon insert" on public.order_items for insert with check (true);
create policy "order_items admin write" on public.order_items for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

create policy "history owner read" on public.order_status_history for select using (
  exists(select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.is_admin(auth.uid())))
);
create policy "history admin write" on public.order_status_history for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- design requests: customer sees own, anyone can submit, admin manages
create policy "designs owner read"   on public.design_requests for select using (user_id = auth.uid() or public.is_admin(auth.uid()));
create policy "designs anon insert"  on public.design_requests for insert with check (true);
create policy "designs admin write"  on public.design_requests for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- store settings: public read, admin write
create policy "settings public read" on public.store_settings for select using (true);
create policy "settings admin write" on public.store_settings for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- ============================================================
-- STORAGE BUCKETS
-- ============================================================
insert into storage.buckets (id, name, public) values
  ('products','products', true),
  ('artwork','artwork', true),
  ('branding','branding', true)
on conflict (id) do nothing;

-- products bucket: public read, admin write
create policy "products read" on storage.objects for select using (bucket_id = 'products');
create policy "products write" on storage.objects for insert with check (bucket_id = 'products' and public.is_admin(auth.uid()));
create policy "products update" on storage.objects for update using (bucket_id = 'products' and public.is_admin(auth.uid()));
create policy "products delete" on storage.objects for delete using (bucket_id = 'products' and public.is_admin(auth.uid()));

-- artwork bucket: public read, anyone can upload (customers submit designs), only admin can delete
create policy "artwork read" on storage.objects for select using (bucket_id = 'artwork');
create policy "artwork upload" on storage.objects for insert with check (bucket_id = 'artwork');
create policy "artwork admin delete" on storage.objects for delete using (bucket_id = 'artwork' and public.is_admin(auth.uid()));

-- branding bucket: public read, admin write
create policy "branding read" on storage.objects for select using (bucket_id = 'branding');
create policy "branding write" on storage.objects for insert with check (bucket_id = 'branding' and public.is_admin(auth.uid()));
create policy "branding update" on storage.objects for update using (bucket_id = 'branding' and public.is_admin(auth.uid()));
create policy "branding delete" on storage.objects for delete using (bucket_id = 'branding' and public.is_admin(auth.uid()));

-- ============================================================
-- SEED DATA
-- ============================================================
insert into public.store_settings (id, description, phone, email, address, announcement, delivery_info, return_policy) values
  (1,
   'Premium clothing, custom printing and branding — made in Nigeria, shipped worldwide.',
   '+2347015119367',
   'hello@xjrprinting.com',
   'Lagos, Nigeria',
   'Free delivery on orders over ₦75,000 — nationwide.',
   'Delivery within Lagos 1–3 working days. Other states 3–7 working days. International rates quoted at checkout.',
   'Returns accepted within 7 days for unworn items in original condition. Custom-printed items are non-returnable unless defective.'
  )
on conflict (id) do nothing;

insert into public.categories (name, slug, sort_order) values
  ('Round Neck T-Shirts','round-neck-t-shirts',1),
  ('Oversized T-Shirts','oversized-t-shirts',2),
  ('Polo Shirts','polo-shirts',3),
  ('Hoodies','hoodies',4),
  ('Sweatshirts','sweatshirts',5),
  ('Corporate Wear','corporate-wear',6),
  ('Custom Printed Clothing','custom-printed-clothing',7),
  ('Accessories','accessories',8)
on conflict (slug) do nothing;

-- 3 SAMPLE products — admin should replace/delete after upload of real stock
insert into public.products (name, slug, description, category_id, price_kobo, sizes, colours, stock, is_active, is_featured, is_new_arrival, is_best_seller)
values
  ('[SAMPLE] Classic Round Neck Tee',
   'sample-classic-round-neck',
   'Sample product for testing. Delete after you upload real stock. 100% cotton, mid-weight.',
   (select id from public.categories where slug='round-neck-t-shirts'),
   850000, array['S','M','L','XL','XXL'], array['Black','White','Orange'], 50, true, true, true, true),
  ('[SAMPLE] Heavyweight Oversized Tee',
   'sample-oversized-tee',
   'Sample product for testing. Delete after you upload real stock. Boxy oversized fit.',
   (select id from public.categories where slug='oversized-t-shirts'),
   1200000, array['M','L','XL','XXL'], array['Black','White'], 30, true, true, true, false),
  ('[SAMPLE] Premium Hoodie',
   'sample-premium-hoodie',
   'Sample product for testing. Delete after you upload real stock. Fleece-lined, kangaroo pocket.',
   (select id from public.categories where slug='hoodies'),
   2200000, array['S','M','L','XL','XXL'], array['Black','Grey','Orange'], 20, true, false, true, true)
on conflict (slug) do nothing;
