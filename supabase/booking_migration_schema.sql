-- Booking module — schema changes + one-time data migration from the
-- retiring tarumt_app project (smyqaegioziojlsozecl), extracted 2026-09.
--
-- Scope of this file: buildings + facilities only. The old project's
-- students/bookings rows were NOT migrated — they all belonged to one
-- account (Janice Teh Li Qian, ID '24WMR07987') that has no equivalent
-- here and was deliberately excluded; the Booking feature itself starts
-- with zero booking history for every real app_enhancement student.
--
-- Run this in the Supabase SQL editor AFTER attendance_schema.sql (it
-- alters public.buildings and public.facilities, defined there).

-- buildings.code -------------------------------------------------------------
-- New, nullable — existing buildings (none yet, in practice) don't have
-- one and don't need one; the 3 migrated rows below do.
alter table public.buildings
  add column if not exists code text;

-- facilities additions --------------------------------------------------------
-- capacity: new, nullable — how many people a bookable room seats. Not
-- part of the original ERD (facilities existed for Attendance's classroom
-- geofencing, which has no notion of "capacity"), but real data exists for
-- it and the Booking UI uses it, so it's worth keeping rather than
-- discarding on the floor.
alter table public.facilities
  add column if not exists capacity integer;

-- latitude/longitude: were NOT NULL because every facility used to mean
-- "a classroom Attendance geofences against," which always has real GPS.
-- A bookable discussion room has no GPS in the source data at all, and
-- forcing one in would mean fabricating a coordinate that Attendance's
-- radius check could later, wrongly, treat as real. Deliberately relaxed
-- rather than backfilled with a fake campus-center point — real
-- coordinates for these specific rooms can be filled in later once
-- available, without another migration.
alter table public.facilities
  alter column latitude drop not null,
  alter column longitude drop not null;

-- Data migration ---------------------------------------------------------
-- Idempotent (matches the existing seed pattern in attendance_schema.sql):
-- safe to re-run, each row only inserts if a building/facility with that
-- name doesn't already exist.
do $$
declare
  v_building_id uuid;
begin
  -- Arena ---------------------------------------------------------------
  -- A building named 'Arena' already existed here before this migration
  -- (unrelated to tarumt_app, 6 floors, no code) — reuse it rather than
  -- create a duplicate, but still backfill its code so it's not the only
  -- migrated building missing one.
  select id into v_building_id from public.buildings where building_name = 'Arena';
  if v_building_id is null then
    insert into public.buildings (building_name, code)
    values ('Arena', 'AR')
    returning id into v_building_id;
  else
    update public.buildings set code = 'AR' where id = v_building_id and code is null;
  end if;

  insert into public.facilities (building_id, room_name, type, status, capacity)
  select v_building_id, 'Arena Discussion Room A1', 'Discussion Room (1 PC)', 'available', 4
  where not exists (
    select 1 from public.facilities where room_name = 'Arena Discussion Room A1'
  );

  -- Cyber Centre ----------------------------------------------------------
  select id into v_building_id from public.buildings where building_name = 'Cyber Centre';
  if v_building_id is null then
    insert into public.buildings (building_name, code)
    values ('Cyber Centre', 'CB')
    returning id into v_building_id;
  end if;

  insert into public.facilities (building_id, room_name, type, status, capacity)
  select v_building_id, 'Cyber Centre Discussion Room 1', 'Discussion Room (1 PC)', 'available', 4
  where not exists (
    select 1 from public.facilities where room_name = 'Cyber Centre Discussion Room 1'
  );

  insert into public.facilities (building_id, room_name, type, status, capacity)
  select v_building_id, 'Cyber Centre Discussion Room 2', 'Discussion Room (2 PCs)', 'available', 6
  where not exists (
    select 1 from public.facilities where room_name = 'Cyber Centre Discussion Room 2'
  );

  -- Library ---------------------------------------------------------------
  select id into v_building_id from public.buildings where building_name = 'Library';
  if v_building_id is null then
    insert into public.buildings (building_name, code)
    values ('Library', 'LIB')
    returning id into v_building_id;
  end if;

  insert into public.facilities (building_id, room_name, type, status, capacity)
  select v_building_id, 'Library Discussion Room A', 'Discussion Room (1 PC)', 'available', 4
  where not exists (
    select 1 from public.facilities where room_name = 'Library Discussion Room A'
  );
end $$;

-- bookings table structure ------------------------------------------------
-- public.bookings already existed as a dead stub (future_modules_schema.sql,
-- zero rows, referenced nowhere in the app) with a different shape:
-- user_id/room_id, start_time/end_time as timestamptz, status default
-- 'confirmed'. The ported booking screens' Supabase calls depend on the
-- OLD tarumt_app table's exact attribute names/formats instead — confirmed
-- by reading its source directly (booking_screen.dart, my_booking_screen.dart):
--   - 'facility_id' (not 'room_id')
--   - a separate 'booking_date' (date), since My Bookings does a plain
--     string compare of it against today to split Active vs Past
--   - 'start_time'/'end_time' as plain "08:00 AM"-style TEXT, not a
--     timestamp — the ported time-slot picker and the _parseTimeString()
--     active/past logic both depend on that exact 12-hour string format
--   - 'pax' (head count) — present in the old schema though the shipped
--     old screens never read/write it; kept for attribute parity
--   - 'status' as one of 5 uppercase values: CONFIRMED, CHECKED IN,
--     CHECKED OUT, CANCELLED, NO SHOW (not lowercase 'confirmed')
-- Structure only, no rows to migrate — the table was already empty.
-- Idempotent: safe to re-run.

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings' and column_name = 'room_id'
  ) then
    alter table public.bookings rename column room_id to facility_id;
  end if;

  if exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'bookings_room_id_idx'
  ) then
    alter index public.bookings_room_id_idx rename to bookings_facility_id_idx;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings'
      and column_name = 'start_time' and data_type <> 'text'
  ) then
    alter table public.bookings drop column start_time;
    alter table public.bookings add column start_time text not null;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings'
      and column_name = 'end_time' and data_type <> 'text'
  ) then
    alter table public.bookings drop column end_time;
    alter table public.bookings add column end_time text not null;
  end if;
end $$;

alter table public.bookings add column if not exists booking_date date;
alter table public.bookings alter column booking_date set not null;

alter table public.bookings add column if not exists pax integer;

alter table public.bookings add column if not exists created_at timestamptz not null default now();

alter table public.bookings alter column status set default 'CONFIRMED';

do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where table_schema = 'public' and table_name = 'bookings'
      and constraint_name = 'bookings_status_check'
  ) then
    alter table public.bookings add constraint bookings_status_check
      check (status in ('CONFIRMED', 'CHECKED IN', 'CHECKED OUT', 'CANCELLED', 'NO SHOW'));
  end if;
end $$;
