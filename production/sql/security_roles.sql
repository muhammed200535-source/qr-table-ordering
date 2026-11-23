-- Masa Demo: rol bazlı yetkiler. security.sql'den SONRA, bir kez çalıştır.
-- Roller: owner (hepsi), kitchen (mutfak), service (garson), cashier (kasa)
-- Bu betik tekrar çalıştırılabilir.

-- 1) personel tablosuna rol sütunu (mevcut kayıtlar 'owner' olarak kalır)
alter table staff add column if not exists role text not null default 'owner';
alter table staff drop constraint if exists staff_role_check;
alter table staff add constraint staff_role_check check (role in ('owner','kitchen','service','cashier'));

-- 2) yardımcı fonksiyonlar
create or replace function public.staff_role() returns text
language sql stable security definer set search_path = public as $$
  select role from staff where email = lower(auth.jwt() ->> 'email')
$$;

-- owner her role sahip sayılır
create or replace function public.has_role(r text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff
                 where email = lower(auth.jwt() ->> 'email') and (role = 'owner' or role = r))
$$;

-- 3) eski "tüm personel her şeyi yapar" politikalarını kaldır
drop policy if exists menu_staff     on menu_items;
drop policy if exists orders_staff   on orders;
drop policy if exists calls_staff    on calls;
drop policy if exists payments_staff on payments;
drop policy if exists tables_staff   on tables;

-- 4) menü: yalnızca owner düzenler (okuma herkese açık, security.sql'deki menu_read kalır)
drop policy if exists menu_owner on menu_items;
create policy menu_owner on menu_items for all to authenticated
  using (public.has_role('owner')) with check (public.has_role('owner'));

-- 5) siparişler: herkes okur (personel), mutfak/servis durum günceller, kasa masayı kapatırken siler
drop policy if exists orders_staff_read    on orders;
drop policy if exists orders_status_update on orders;
drop policy if exists orders_cashier_del   on orders;
drop policy if exists orders_owner_insert  on orders;
create policy orders_staff_read    on orders for select to authenticated using (public.is_staff());
create policy orders_status_update on orders for update to authenticated
  using (public.has_role('kitchen') or public.has_role('service'))
  with check (public.has_role('kitchen') or public.has_role('service'));
create policy orders_cashier_del   on orders for delete to authenticated using (public.has_role('cashier'));
create policy orders_owner_insert  on orders for insert to authenticated with check (public.has_role('owner'));

-- 6) çağrılar: personel okur, servis ve kasa temizler
drop policy if exists calls_staff_read   on calls;
drop policy if exists calls_clear        on calls;
drop policy if exists calls_owner_insert on calls;
create policy calls_staff_read   on calls for select to authenticated using (public.is_staff());
create policy calls_clear        on calls for delete to authenticated
  using (public.has_role('service') or public.has_role('cashier'));
create policy calls_owner_insert on calls for insert to authenticated with check (public.has_role('owner'));

-- 7) ödemeler: yalnızca kasa (ve owner) okur/yazar, yalnızca owner siler
drop policy if exists payments_read         on payments;
drop policy if exists payments_insert       on payments;
drop policy if exists payments_owner_delete on payments;
create policy payments_read         on payments for select to authenticated using (public.has_role('cashier'));
create policy payments_insert       on payments for insert to authenticated with check (public.has_role('cashier'));
create policy payments_owner_delete on payments for delete to authenticated using (public.has_role('owner'));

-- 8) masa QR anahtarları: yalnızca owner
drop policy if exists tables_owner on tables;
create policy tables_owner on tables for all to authenticated
  using (public.has_role('owner')) with check (public.has_role('owner'));

-- Personel ekleme örnekleri (önce Authentication > Users bölümünden hesabı aç):
-- insert into staff (email, role) values ('mutfak@ornek.com',  'kitchen')
--   on conflict (email) do update set role = excluded.role;
-- insert into staff (email, role) values ('garson@ornek.com',  'service')
--   on conflict (email) do update set role = excluded.role;
-- insert into staff (email, role) values ('kasa@ornek.com',    'cashier')
--   on conflict (email) do update set role = excluded.role;
