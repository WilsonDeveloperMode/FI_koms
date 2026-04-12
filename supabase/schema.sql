-- Francis Interior Komisi schema
-- Run this in Supabase SQL editor.

create extension if not exists "pgcrypto";

create type public.app_role as enum ('direksi', 'staff');
create type public.payment_status as enum ('outstanding', 'paid');

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
create unique index if not exists idx_profiles_username_unique on public.profiles(username);
create unique index if not exists idx_profiles_email_unique on public.profiles(email);

alter table public.profiles
  alter column username set not null,
  alter column email set not null;

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

-- profiles
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

-- clients
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

-- contracts
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

-- contract_pics
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

-- Automatically keep updated_at fresh
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_contract_pics_updated_at on public.contract_pics;
create trigger trg_contract_pics_updated_at
before update on public.contract_pics
for each row
execute function public.set_updated_at();
