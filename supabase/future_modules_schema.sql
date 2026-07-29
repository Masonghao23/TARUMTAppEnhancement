-- Structure-only tables for the Car Parking and Notification modules, per
-- the ERD (Figure 4.9) and Class Diagram (Figure 4.10) in the Project I
-- report. These exist now so the overall schema matches the design
-- document up front, but NONE of them have RLS policies or grants yet —
-- row level security is enabled with no policies, which means the
-- `authenticated` role can't read or write them at all. Add policies,
-- grants, and RPCs for each table when its module is actually built.
--
-- Run this in the Supabase SQL editor AFTER schema.sql and
-- attendance_schema.sql (it references public.profiles and
-- public.facilities).

-- AccessLog -----------------------------------------------------------------
create table if not exists public.access_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  room_id uuid references public.facilities (id) on delete set null,
  occurred_at timestamptz not null default now(),
  action text not null,
  status text not null default 'pending'
);

create index if not exists access_logs_user_id_idx on public.access_logs (user_id);
create index if not exists access_logs_room_id_idx on public.access_logs (room_id);

-- Notification ----------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  message text not null,
  sent_at timestamptz not null default now(),
  is_read boolean not null default false,
  type text not null
);

create index if not exists notifications_user_id_idx on public.notifications (user_id);

-- NotificationPreference -------------------------------------------------------
create table if not exists public.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles (id) on delete cascade,
  allow_attendance_alerts boolean not null default true,
  allow_parking_alerts boolean not null default true,
  allow_class_reminders boolean not null default true,
  allow_booking_reminders boolean not null default true
);

-- RegisteredVehicle -------------------------------------------------------------
create table if not exists public.registered_vehicles (
  plate_num text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  vehicle_model text
);

create index if not exists registered_vehicles_user_id_idx on public.registered_vehicles (user_id);

-- ParkingSlot --------------------------------------------------------------------
create table if not exists public.parking_slots (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'available'
);

-- ParkingReservation --------------------------------------------------------------
create table if not exists public.parking_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  slot_id uuid not null references public.parking_slots (id) on delete cascade,
  plate_num text references public.registered_vehicles (plate_num) on delete set null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  total_fee numeric,
  status text not null default 'reserved'
);

create index if not exists parking_reservations_user_id_idx on public.parking_reservations (user_id);
create index if not exists parking_reservations_slot_id_idx on public.parking_reservations (slot_id);

-- Booking (generic facility booking, e.g. study rooms) ----------------------------
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  room_id uuid not null references public.facilities (id) on delete cascade,
  start_time timestamptz not null,
  end_time timestamptz not null,
  status text not null default 'confirmed'
);

create index if not exists bookings_user_id_idx on public.bookings (user_id);
create index if not exists bookings_room_id_idx on public.bookings (room_id);

alter table public.access_logs enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.registered_vehicles enable row level security;
alter table public.parking_slots enable row level security;
alter table public.parking_reservations enable row level security;
alter table public.bookings enable row level security;
