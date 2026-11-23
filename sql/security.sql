-- Masa Demo: güvenlik betiği. setup.sql'den SONRA, bir kez çalıştır.
-- Sonuç: müşteri sadece kendi masasına sipariş verebilir, personel ekranları giriş ister.

create table if not exists tables (
  table_no int primary key,
  token text not null default replace(gen_random_uuid()::text, '-', '')
);
insert into tables (table_no) select g from generate_series(1, 20) g on conflict do nothing;

create table if not exists staff (email text primary key);

create or replace function public.guest_table() returns int
language sql stable security definer set search_path = public as $$
  select table_no from tables
  where token = (nullif(current_setting('request.headers', true), '')::json ->> 'x-table-token')
$$;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where email = lower(auth.jwt() ->> 'email'))
$$;

-- Eski açık demo politikalarını kaldır
do $$
declare t text;
begin
  foreach t in array array['menu_items','orders','calls','payments'] loop
    execute format('drop policy if exists "demo_all" on %I', t);
  end loop;
end $$;

alter table tables enable row level security;
alter table staff enable row level security;   -- politika yok: yalnızca panelden düzenlenir

-- Menü: herkes okur, personel düzenler
create policy menu_read  on menu_items for select to anon, authenticated using (true);
create policy menu_staff on menu_items for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Siparişler ve çağrılar: müşteri yalnızca kendi masasını görür ve yazar
create policy orders_guest_select on orders for select to anon using (table_no = public.guest_table());
create policy orders_guest_insert on orders for insert to anon with check (table_no = public.guest_table() and status = 'new');
create policy orders_staff on orders for all to authenticated using (public.is_staff()) with check (public.is_staff());

create policy calls_guest_select on calls for select to anon using (table_no = public.guest_table());
create policy calls_guest_insert on calls for insert to anon with check (table_no = public.guest_table());
create policy calls_staff on calls for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Ödemeler ve masa anahtarları: yalnızca personel
create policy payments_staff on payments for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy tables_staff on tables for all to authenticated using (public.is_staff()) with check (public.is_staff());
