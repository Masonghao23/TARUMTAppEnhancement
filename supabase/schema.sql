-- User Management Module schema
-- Run this in the Supabase SQL editor (Project > SQL Editor > New query).

create extension if not exists pgcrypto;

-- Profile data for each auth.users row (Supabase Auth owns password hashing
-- and session tokens, so those columns from the report's ERD are not
-- duplicated here).
--
-- campus_id format depends on role:
--   student -> 2-digit enrolment year + 5-digit index, e.g. "2408009"
--   staff   -> 4-digit numeric ID, e.g. "1234"
--   admin   -> unrestricted (system account, not campus-issued)
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  campus_id text not null unique,
  name text not null default '',
  email text not null,
  role text not null default 'student' check (role in ('student', 'staff', 'admin')),
  rfid_uid text,
  created_at timestamptz not null default now(),
  constraint profiles_campus_id_format check (
    (role = 'student' and campus_id ~ '^[0-9]{7}$')
    or (role = 'staff' and campus_id ~ '^[0-9]{4}$')
    or (role = 'admin')
  )
);

create table if not exists public.user_devices (
  device_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  device_identifier text not null,
  device_model text,
  status text not null default 'active' check (status in ('active', 'replaced')),
  bind_date timestamptz not null default now()
);

create index if not exists user_devices_user_id_idx on public.user_devices (user_id);
create index if not exists user_devices_identifier_idx on public.user_devices (device_identifier);

-- Auto-create a profile row whenever a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, campus_id, name, email, role)
  values (
    new.id,
    new.raw_user_meta_data ->> 'campus_id',
    coalesce(new.raw_user_meta_data ->> 'name', ''),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'role', 'student')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Security-definer check used by device binding so a student cannot see
-- other users' device rows directly, but the app can still detect a
-- conflicting bind.
create or replace function public.is_device_bound_to_other_user(
  p_device_identifier text,
  p_user_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_devices
    where device_identifier = p_device_identifier
      and status = 'active'
      and user_id <> p_user_id
  );
$$;

grant execute on function public.is_device_bound_to_other_user(text, uuid) to authenticated;

-- Lets a user explicitly take over a device that another account left bound
-- to it (Table 4.2 alt flow A1: "Change ID Binding to Current Device").
create or replace function public.release_device_from_other_users(
  p_device_identifier text,
  p_new_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_devices
  set status = 'replaced'
  where device_identifier = p_device_identifier
    and status = 'active'
    and user_id <> p_new_user_id;
end;
$$;

grant execute on function public.release_device_from_other_users(text, uuid) to authenticated;

-- RLS policies only filter *rows*; the authenticated role still needs the
-- base table grant or every query 42501s regardless of policy outcome.
--
-- profiles gets SELECT only. RLS has no column-level enforcement, so any
-- UPDATE grant here — even paired with a row-scoped "you may edit your own
-- row" policy — lets a signed-in user PATCH their own row's `role` to
-- 'admin' straight through PostgREST, bypassing the app entirely (verified
-- exploitable). New rows come from the handle_new_user trigger (security
-- definer, unaffected by this grant); the client only ever reads profiles.
-- If a profile-edit screen is ever built, add a security-definer RPC that
-- whitelists editable columns (name, rfid_uid) — never a raw UPDATE grant.
grant select on public.profiles to authenticated;
grant select, insert, update on public.user_devices to authenticated;

alter table public.profiles enable row level security;
alter table public.user_devices enable row level security;

-- A policy on public.profiles cannot query public.profiles directly to check
-- the caller's role — Postgres detects that as infinite recursion (error
-- 42P17). Routing the lookup through a SECURITY DEFINER function avoids it,
-- because such functions bypass RLS on the tables they query internally.
create or replace function public.current_user_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

grant execute on function public.current_user_role() to authenticated;

drop policy if exists "profiles_select_self" on public.profiles;
create policy "profiles_select_self" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_select_staff" on public.profiles;
create policy "profiles_select_staff" on public.profiles
  for select using (public.current_user_role() in ('staff', 'admin'));

-- No UPDATE policy on profiles on purpose — see the grant note above.
-- Dropped rather than left in place so a future re-added UPDATE grant
-- defaults to RLS-denied instead of silently reopening the hole.
drop policy if exists "profiles_update_self" on public.profiles;

drop policy if exists "user_devices_select_own" on public.user_devices;
create policy "user_devices_select_own" on public.user_devices
  for select using (auth.uid() = user_id);

drop policy if exists "user_devices_insert_own" on public.user_devices;
create policy "user_devices_insert_own" on public.user_devices
  for insert with check (auth.uid() = user_id);

drop policy if exists "user_devices_update_own" on public.user_devices;
create policy "user_devices_update_own" on public.user_devices
  for update using (auth.uid() = user_id);

-- Seed a single default admin account so there is a first user able to
-- create staff/student accounts from within the app. This inserts directly
-- into Supabase Auth's tables (the same tables the Auth API manages), which
-- is a well-known pattern for seeding but is version-sensitive — if this
-- block errors on your project, just create a user from the Dashboard
-- (Authentication > Users > Add user) instead and set role='admin' on its
-- row in public.profiles afterwards.
--
-- CHANGE THIS PASSWORD IMMEDIATELY AFTER FIRST LOGIN.
do $$
declare
  admin_id uuid := gen_random_uuid();
  admin_email text := 'admin@tarumt.edu.my';
  admin_password text := 'Testing123';
begin
  if not exists (select 1 from auth.users where email = admin_email) then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change, email_change_token_new, email_change_token_current
    ) values (
      '00000000-0000-0000-0000-000000000000',
      admin_id,
      'authenticated',
      'authenticated',
      admin_email,
      crypt(admin_password, gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object(
        'name', 'System Admin',
        'campus_id', 'ADMIN001',
        'role', 'admin'
      ),
      now(), now(), '', '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(),
      admin_id,
      admin_id::text,
      jsonb_build_object('sub', admin_id::text, 'email', admin_email),
      'email',
      now(), now(), now()
    );
  end if;
end $$;
