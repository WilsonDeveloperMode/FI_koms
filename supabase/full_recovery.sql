-- FULL RECOVERY SQL
-- Francis Interior - Komisi App
-- Safe/idempotent: can be re-run to repair schema, policies, RPC, and triggers.

begin;

create extension if not exists "pgcrypto";

do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type public.app_role as enum ('direksi', 'staff');
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'payment_status') then
    create type public.payment_status as enum ('outstanding', 'paid');
  end if;
end $$;

insert into storage.buckets (id, name, public)
values ('komisi-files', 'komisi-files', true)
on conflict (id) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  username text unique,
  email text unique,
  role public.app_role not null default 'staff',
  phone text,
  created_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists username text,
  add column if not exists email text;

create unique index if not exists idx_profiles_username_unique on public.profiles(username);
create unique index if not exists idx_profiles_email_unique on public.profiles(email);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text not null,
  phone_number text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.contracts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  contract_name text not null,
  contract_file_url text,
  commission_month date not null default date_trunc('month', now())::date,
  contract_price numeric(14,2) not null check (contract_price >= 0),
  commission_percent numeric(5,2) not null check (commission_percent >= 0 and commission_percent <= 100),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.contracts
  add column if not exists commission_month date not null default date_trunc('month', now())::date;

create table if not exists public.contract_pics (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.contracts(id) on delete cascade,
  staff_id uuid not null references public.profiles(id) on delete cascade,
  commission_value numeric(14,2) not null check (commission_value >= 0),
  allocation_percent numeric(5,2) check (allocation_percent >= 0 and allocation_percent <= 100),
  weighing text,
  contact_amount numeric(14,2),
  penjatahan text,
  payment_status public.payment_status not null default 'outstanding',
  bukti_bayar_url text,
  updated_at timestamptz not null default now(),
  unique (contract_id, staff_id)
);

alter table public.contract_pics
  add column if not exists allocation_percent numeric(5,2);

create table if not exists public.monthly_payouts (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.profiles(id) on delete cascade,
  payout_month date not null,
  status public.payment_status not null default 'outstanding',
  proof_url text,
  updated_at timestamptz not null default now(),
  unique (staff_id, payout_month)
);

create index if not exists idx_clients_name on public.clients(name);
create index if not exists idx_contracts_client_id on public.contracts(client_id);
create index if not exists idx_contracts_commission_month on public.contracts(commission_month);
create index if not exists idx_contract_pics_staff_id on public.contract_pics(staff_id);

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.contracts enable row level security;
alter table public.contract_pics enable row level security;
alter table public.monthly_payouts enable row level security;

create or replace function public.is_direksi(uid uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid and p.role = 'direksi'
  );
$$;

drop policy if exists "profiles self read" on public.profiles;
create policy "profiles self read"
on public.profiles for select
to authenticated
using (id = auth.uid() or public.is_direksi(auth.uid()));

drop policy if exists "direksi manage profiles" on public.profiles;
create policy "direksi manage profiles"
on public.profiles for all
to authenticated
using (public.is_direksi(auth.uid()))
with check (public.is_direksi(auth.uid()));

drop policy if exists "staff can read clients" on public.clients;
create policy "staff can read clients"
on public.clients for select
to authenticated
using (true);

drop policy if exists "direksi manage clients" on public.clients;
create policy "direksi manage clients"
on public.clients for all
to authenticated
using (public.is_direksi(auth.uid()))
with check (public.is_direksi(auth.uid()));

drop policy if exists "staff can read contracts" on public.contracts;
create policy "staff can read contracts"
on public.contracts for select
to authenticated
using (true);

drop policy if exists "direksi manage contracts" on public.contracts;
create policy "direksi manage contracts"
on public.contracts for all
to authenticated
using (public.is_direksi(auth.uid()))
with check (public.is_direksi(auth.uid()));

drop policy if exists "staff read own commissions" on public.contract_pics;
create policy "staff read own commissions"
on public.contract_pics for select
to authenticated
using (staff_id = auth.uid() or public.is_direksi(auth.uid()));

drop policy if exists "direksi manage contract pics" on public.contract_pics;
create policy "direksi manage contract pics"
on public.contract_pics for all
to authenticated
using (public.is_direksi(auth.uid()))
with check (public.is_direksi(auth.uid()));

drop policy if exists "staff read own monthly payouts" on public.monthly_payouts;
create policy "staff read own monthly payouts"
on public.monthly_payouts for select
to authenticated
using (staff_id = auth.uid() or public.is_direksi(auth.uid()));

drop policy if exists "direksi manage monthly payouts" on public.monthly_payouts;
create policy "direksi manage monthly payouts"
on public.monthly_payouts for all
to authenticated
using (public.is_direksi(auth.uid()))
with check (public.is_direksi(auth.uid()));

drop policy if exists "komisi files authenticated read" on storage.objects;
create policy "komisi files authenticated read"
on storage.objects for select
to authenticated
using (bucket_id = 'komisi-files');

drop policy if exists "komisi files direksi upload" on storage.objects;
create policy "komisi files direksi upload"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'komisi-files'
  and public.is_direksi(auth.uid())
);

drop policy if exists "komisi files direksi update" on storage.objects;
create policy "komisi files direksi update"
on storage.objects for update
to authenticated
using (
  bucket_id = 'komisi-files'
  and public.is_direksi(auth.uid())
)
with check (
  bucket_id = 'komisi-files'
  and public.is_direksi(auth.uid())
);

create or replace function public.get_login_email(p_username text)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select p.email
  from public.profiles p
  where lower(p.username) = lower(trim(p_username))
  limit 1;
$$;

revoke all on function public.get_login_email(text) from public;
grant execute on function public.get_login_email(text) to anon, authenticated;

create or replace function public.get_contract_pic_count(p_contract_id uuid)
returns integer
language sql
security definer
set search_path = public
stable
as $$
  select count(*)::int
  from public.contract_pics cp
  where cp.contract_id = p_contract_id;
$$;

revoke all on function public.get_contract_pic_count(uuid) from public;
grant execute on function public.get_contract_pic_count(uuid) to authenticated;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.sync_contract_pic_legacy_fields(p_contract_id uuid)
returns void
language sql
as $$
  with pic_count as (
    select count(*)::numeric as total
    from public.contract_pics
    where contract_id = p_contract_id
  )
  update public.contract_pics cp
  set
    contact_amount = c.contract_price,
    weighing = concat(
      coalesce(cp.allocation_percent, round(100 / greatest(pc.total, 1), 2)),
      '%'
    ),
    penjatahan = cp.commission_value::text
  from public.contracts c, pic_count pc
  where cp.contract_id = p_contract_id
    and c.id = p_contract_id;
$$;

create or replace function public.trg_sync_contract_pic_legacy_fields()
returns trigger
language plpgsql
as $$
begin
  if pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  perform public.sync_contract_pic_legacy_fields(
    coalesce(new.contract_id, old.contract_id)
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.trg_sync_contract_pic_after_contract_update()
returns trigger
language plpgsql
as $$
begin
  perform public.sync_contract_pic_legacy_fields(new.id);
  return new;
end;
$$;

drop trigger if exists trg_contract_pics_updated_at on public.contract_pics;
create trigger trg_contract_pics_updated_at
before update on public.contract_pics
for each row
execute function public.set_updated_at();

drop trigger if exists trg_contract_pics_sync_legacy_fields on public.contract_pics;
create trigger trg_contract_pics_sync_legacy_fields
after insert or update or delete on public.contract_pics
for each row
execute function public.trg_sync_contract_pic_legacy_fields();

drop trigger if exists trg_contracts_sync_pic_legacy_fields on public.contracts;
create trigger trg_contracts_sync_pic_legacy_fields
after update of contract_price on public.contracts
for each row
execute function public.trg_sync_contract_pic_after_contract_update();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_username text;
  final_username text;
  n int := 0;
begin
  base_username := lower(split_part(new.email, '@', 1));
  final_username := base_username;

  while exists (select 1 from public.profiles p where p.username = final_username) loop
    n := n + 1;
    final_username := base_username || '_' || n::text;
  end loop;

  insert into public.profiles (id, username, email, full_name, role, phone)
  values (
    new.id,
    final_username,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', base_username),
    'staff',
    null
  )
  on conflict (id) do update
  set username = excluded.username,
      email = excluded.email;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

update public.contract_pics cp
set
  contact_amount = c.contract_price,
  weighing = concat(
    coalesce(cp.allocation_percent, round(100 / greatest(pc.total, 1), 2)),
    '%'
  ),
  penjatahan = cp.commission_value::text
from public.contracts c,
(
  select contract_id, count(*)::numeric as total
  from public.contract_pics
  group by contract_id
) pc
where c.id = cp.contract_id
  and pc.contract_id = cp.contract_id
  and (
    cp.contact_amount is null
    or cp.weighing is null
    or cp.penjatahan is null
  );

drop view if exists public.v_contract_pics_readable;
create view public.v_contract_pics_readable as
select
  cp.id,
  cp.contract_id,
  cp.staff_id,
  p.username as staff_username,
  p.full_name as staff_full_name,
  cp.commission_value,
  cp.allocation_percent,
  cp.weighing,
  cp.contact_amount,
  cp.penjatahan,
  cp.payment_status,
  cp.bukti_bayar_url,
  cp.updated_at
from public.contract_pics cp
left join public.profiles p on p.id = cp.staff_id;

commit;
