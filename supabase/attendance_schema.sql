-- Attendance Module schema — mirrors the ERD (Figure 4.9) and Class Diagram
-- (Figure 4.10/4.11) in the Project I report: Course, CourseEnrollment,
-- Building, Facility, ClassSession, AttendanceRecord.
--
-- Two deliberate extensions beyond the diagram, called out where they
-- appear below, because the diagram doesn't fully specify them:
--   1. class_sessions.lecturer_id — the diagram has no FK from ClassSession
--      to a staff member at all, but Supabase RLS needs an owner column to
--      authorize who may control a live session.
--   2. facilities.latitude/longitude/radius_meters — Facility's coordX/Y/Z
--      + modelPath are indoor map-model coordinates (for a 2D/3D facility
--      view, most likely the Car Parking module's floor map), not usable
--      against a phone's real GPS reading. Geofencing needs real lat/long.
--
-- Run this in the Supabase SQL editor AFTER schema.sql (it depends on
-- public.profiles).

create extension if not exists pgcrypto;

-- This redesigns class_sessions/attendance_records from the ad-hoc version
-- run earlier today to the ERD-aligned version below. No real check-ins
-- have been recorded against the old shape yet, so this drops and
-- recreates both — if you've since collected real attendance data, back
-- it up before re-running this file.
drop table if exists public.attendance_records cascade;
drop table if exists public.class_sessions cascade;

-- Course -----------------------------------------------------------------
create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  course_code text not null unique,
  course_name text not null
);

-- CourseEnrollment --------------------------------------------------------
create table if not exists public.course_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles (id) on delete cascade,
  course_id uuid not null references public.courses (id) on delete cascade,
  unique (student_id, course_id)
);

create index if not exists course_enrollments_student_id_idx on public.course_enrollments (student_id);
create index if not exists course_enrollments_course_id_idx on public.course_enrollments (course_id);

-- Building ------------------------------------------------------------------
create table if not exists public.buildings (
  id uuid primary key default gen_random_uuid(),
  building_name text not null,
  total_floors integer,
  map_boundary_coords text
);

-- Facility ("room") --------------------------------------------------------
-- coord_x/y/z + model_path are indoor map-model coordinates per the ERD;
-- latitude/longitude/radius_meters are the extension noted above, used for
-- real GPS geofencing during attendance check-in.
create table if not exists public.facilities (
  id uuid primary key default gen_random_uuid(),
  building_id uuid references public.buildings (id) on delete set null,
  room_name text not null,
  type text,
  status text not null default 'available',
  model_path text,
  coord_x double precision,
  coord_y double precision,
  coord_z double precision,
  latitude double precision not null,
  longitude double precision not null,
  radius_meters integer not null default 50
);

create index if not exists facilities_building_id_idx on public.facilities (building_id);

-- ClassSession --------------------------------------------------------------
-- dynamic_qr_seed is generated once per session; the QR the lecturer shows
-- is HMAC(seed, time_window) recomputed locally every qr_interval_seconds
-- with no further writes to this row — see submit_attendance() below for
-- the matching server-side check.
create table if not exists public.class_sessions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  room_id uuid not null references public.facilities (id) on delete restrict,
  lecturer_id uuid not null references public.profiles (id) on delete cascade,
  dynamic_qr_seed text not null default encode(gen_random_bytes(20), 'hex'),
  qr_interval_seconds integer not null default 20,
  status text not null default 'active' check (status in ('active', 'ended')),
  start_time timestamptz not null default now(),
  end_time timestamptz
);

create index if not exists class_sessions_course_id_idx on public.class_sessions (course_id);
create index if not exists class_sessions_lecturer_id_idx on public.class_sessions (lecturer_id);

-- AttendanceRecord ------------------------------------------------------------
-- device_identifier/distance_meters are an audit-trail extension (a
-- snapshot of which device/how far, for staff dispute resolution) — the
-- authoritative device-binding check still happens against user_devices.
create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.class_sessions (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  scan_timestamp timestamptz not null default now(),
  status text not null default 'present' check (status in ('present', 'late')),
  device_identifier text not null,
  distance_meters double precision,
  unique (session_id, student_id)
);

create index if not exists attendance_records_session_id_idx on public.attendance_records (session_id);
create index if not exists attendance_records_student_id_idx on public.attendance_records (student_id);

create or replace function public.haversine_meters(
  lat1 double precision, lon1 double precision,
  lat2 double precision, lon2 double precision
) returns double precision
language sql
immutable
as $$
  select 6371000 * 2 * asin(
    sqrt(
      sin(radians(lat2 - lat1) / 2) ^ 2 +
      cos(radians(lat1)) * cos(radians(lat2)) *
      sin(radians(lon2 - lon1) / 2) ^ 2
    )
  );
$$;

-- create or replace only replaces a function with the exact same parameter
-- types — p_token changed from uuid (old ad-hoc design) to text (seed-based
-- HMAC design), so the two versions became separate overloads instead of
-- one being replaced, and PostgREST couldn't tell them apart (PGRST203).
-- Drop the old-signature overload explicitly before redefining it.
drop function if exists public.submit_attendance(uuid, uuid, text, double precision, double precision);

-- Single entry point for checking in. Runs as security definer so it can
-- see the caller's bound device (user_devices), the session's QR seed, and
-- the room's coordinates without relying on the client to self-report a
-- pass/fail — every rule (enrollment, token freshness, geofence, device
-- binding) is enforced server-side.
create or replace function public.submit_attendance(
  p_session_id uuid,
  p_token text,
  p_device_identifier text,
  p_latitude double precision,
  p_longitude double precision
) returns jsonb
language plpgsql
security definer
-- pgcrypto (hmac()) lives in the `extensions` schema on Supabase projects,
-- not `public` — needs to be on the path or hmac() can't be resolved.
set search_path = public, extensions
as $$
declare
  v_session record;
  v_facility record;
  v_distance double precision;
  v_existing record;
  v_window bigint;
begin
  select * into v_session from public.class_sessions where id = p_session_id;

  if not found then
    return jsonb_build_object('success', false, 'reason', 'Session not found.');
  end if;

  if v_session.status <> 'active' then
    return jsonb_build_object('success', false, 'reason', 'This class session has ended.');
  end if;

  if not exists (
    select 1 from public.course_enrollments
    where course_id = v_session.course_id and student_id = auth.uid()
  ) then
    return jsonb_build_object('success', false, 'reason', 'You are not enrolled in this class.');
  end if;

  -- Tolerance covers the current window plus the last 2 — a phone's GPS
  -- fix can easily take 20-40s on a cold start, and that happens *after*
  -- the QR was scanned, so a tight 1-window tolerance rejects honest
  -- students who scanned in time but whose location fetch was slow.
  v_window := floor(extract(epoch from now()) / v_session.qr_interval_seconds);
  if p_token <> encode(hmac(v_window::text, v_session.dynamic_qr_seed, 'sha256'), 'hex')
    and p_token <> encode(hmac((v_window - 1)::text, v_session.dynamic_qr_seed, 'sha256'), 'hex')
    and p_token <> encode(hmac((v_window - 2)::text, v_session.dynamic_qr_seed, 'sha256'), 'hex')
  then
    return jsonb_build_object('success', false, 'reason', 'QR code has expired — ask the lecturer to rescan.');
  end if;

  if not exists (
    select 1 from public.user_devices
    where user_id = auth.uid() and status = 'active' and device_identifier = p_device_identifier
  ) then
    return jsonb_build_object('success', false, 'reason', 'This device is not bound to your account.');
  end if;

  select * into v_facility from public.facilities where id = v_session.room_id;
  v_distance := public.haversine_meters(v_facility.latitude, v_facility.longitude, p_latitude, p_longitude);
  if v_distance > v_facility.radius_meters then
    return jsonb_build_object(
      'success', false,
      'reason', 'You are too far from the class location (' || round(v_distance) || 'm away).'
    );
  end if;

  select * into v_existing from public.attendance_records
  where session_id = p_session_id and student_id = auth.uid();

  if found then
    return jsonb_build_object(
      'success', true,
      'already_checked_in', true,
      'distance_meters', v_distance,
      'checked_in_at', v_existing.scan_timestamp
    );
  end if;

  -- on conflict do nothing: a concurrent second scan, or a lecturer's
  -- manual mark (set_attendance_status) landing between the select above
  -- and this insert, would otherwise raise an unhandled unique-violation
  -- straight to the client instead of the graceful "already checked in".
  insert into public.attendance_records (session_id, student_id, device_identifier, distance_meters)
  values (p_session_id, auth.uid(), p_device_identifier, v_distance)
  on conflict (session_id, student_id) do nothing;

  if not found then
    select * into v_existing from public.attendance_records
    where session_id = p_session_id and student_id = auth.uid();
    return jsonb_build_object(
      'success', true,
      'already_checked_in', true,
      'distance_meters', v_distance,
      'checked_in_at', v_existing.scan_timestamp
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'already_checked_in', false,
    'distance_meters', v_distance,
    'checked_in_at', now()
  );
end;
$$;

grant execute on function public.submit_attendance(uuid, text, text, double precision, double precision) to authenticated;

-- Returns the seed only to the session's own lecturer (or an admin) so the
-- lecturer's screen can compute HMAC(seed, window) locally every tick. This
-- is the *only* way to read a seed — see the column-level grant below,
-- which excludes dynamic_qr_seed from the general SELECT grant entirely.
-- Without this, any enrolled student could read their class's seed
-- straight off the row and fabricate a valid token without ever scanning a
-- live QR, defeating the point of a dynamic code.
create or replace function public.get_session_seed(p_session_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seed text;
begin
  select dynamic_qr_seed into v_seed
  from public.class_sessions
  where id = p_session_id
    and (lecturer_id = auth.uid() or public.current_user_role() = 'admin');

  return v_seed;
end;
$$;

grant execute on function public.get_session_seed(uuid) to authenticated;

-- Percentage helper for FR08 ("display real-time attendance records with
-- percentage") — denominator is every session ever held for the course,
-- numerator is how many the student actually attended.
create or replace function public.calculate_attendance_percentage(
  p_student_id uuid,
  p_course_id uuid
) returns double precision
language sql
stable
security definer
set search_path = public
as $$
  select case when total.count = 0 then 0
    else round((attended.count::numeric / total.count) * 100, 1)
  end
  from
    (select count(*) as count from public.class_sessions where course_id = p_course_id) as total,
    (
      select count(*) as count
      from public.attendance_records ar
      join public.class_sessions cs on cs.id = ar.session_id
      where cs.course_id = p_course_id and ar.student_id = p_student_id
    ) as attended;
$$;

grant execute on function public.calculate_attendance_percentage(uuid, uuid) to authenticated;

-- class_sessions' SELECT policy needs to check attendance_records, and
-- attendance_records' SELECT policy needs to check class_sessions — a
-- direct subquery in each would make Postgres re-evaluate the other
-- table's RLS policy while evaluating this one, and recurse forever
-- (42P17). Routing each cross-table check through a SECURITY DEFINER
-- function avoids it, exactly like current_user_role() already does for
-- public.profiles in schema.sql.
create or replace function public.is_lecturer_of_session(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.class_sessions
    where id = p_session_id and lecturer_id = auth.uid()
  );
$$;

grant execute on function public.is_lecturer_of_session(uuid) to authenticated;

create or replace function public.has_attended_session(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.attendance_records
    where session_id = p_session_id and student_id = auth.uid()
  );
$$;

grant execute on function public.has_attended_session(uuid) to authenticated;

-- RLS policies only filter *rows*; the authenticated role still needs the
-- base table grant or every query 42501s regardless of policy outcome.
-- attendance_records has no insert/update grant here on purpose — the only
-- way to write a row is through submit_attendance(), which runs as security
-- definer and bypasses RLS. courses/course_enrollments/buildings/facilities
-- have no insert/update grant either — until an admin CRUD screen exists,
-- they're managed directly via SQL (see the seed data below).
grant select on public.courses to authenticated;
grant select on public.course_enrollments to authenticated;
grant select on public.buildings to authenticated;
grant select on public.facilities to authenticated;
-- Column-level grant deliberately excludes dynamic_qr_seed — it must only
-- ever be readable through get_session_seed() above.
grant select (
  id, course_id, room_id, lecturer_id, qr_interval_seconds,
  status, start_time, end_time
) on public.class_sessions to authenticated;
-- UPDATE is column-restricted to match: endSession() only flips status +
-- end_time. Without this, class_sessions_update_own (row-scoped, no
-- with-check) lets a lecturer PATCH course_id / room_id /
-- qr_interval_seconds / schedule_id on their own session, bypassing every
-- check in start_scheduled_session. INSERT stays broad for now — it's
-- gated by class_sessions_insert_staff (staff role required) and the
-- normal path is the start_scheduled_session RPC; tighten later.
grant insert on public.class_sessions to authenticated;
grant update (status, end_time) on public.class_sessions to authenticated;
grant select on public.attendance_records to authenticated;

alter table public.courses enable row level security;
alter table public.course_enrollments enable row level security;
alter table public.buildings enable row level security;
alter table public.facilities enable row level security;
alter table public.class_sessions enable row level security;
alter table public.attendance_records enable row level security;

drop policy if exists "courses_select_all" on public.courses;
create policy "courses_select_all" on public.courses for select using (true);

drop policy if exists "buildings_select_all" on public.buildings;
create policy "buildings_select_all" on public.buildings for select using (true);

drop policy if exists "facilities_select_all" on public.facilities;
create policy "facilities_select_all" on public.facilities for select using (true);

drop policy if exists "course_enrollments_select_own_or_staff" on public.course_enrollments;
create policy "course_enrollments_select_own_or_staff" on public.course_enrollments
  for select using (
    auth.uid() = student_id
    or public.current_user_role() in ('staff', 'admin')
  );

drop policy if exists "class_sessions_select_lecturer_or_admin" on public.class_sessions;
create policy "class_sessions_select_lecturer_or_admin" on public.class_sessions
  for select using (
    auth.uid() = lecturer_id
    or public.current_user_role() = 'admin'
    or public.has_attended_session(id)
  );

drop policy if exists "class_sessions_insert_staff" on public.class_sessions;
create policy "class_sessions_insert_staff" on public.class_sessions
  for insert with check (
    auth.uid() = lecturer_id
    and public.current_user_role() in ('staff', 'admin')
  );

drop policy if exists "class_sessions_update_own" on public.class_sessions;
create policy "class_sessions_update_own" on public.class_sessions
  for update using (auth.uid() = lecturer_id);

drop policy if exists "attendance_records_select_own_or_lecturer" on public.attendance_records;
create policy "attendance_records_select_own_or_lecturer" on public.attendance_records
  for select using (
    auth.uid() = student_id
    or public.current_user_role() = 'admin'
    or public.is_lecturer_of_session(session_id)
  );

-- Let staff subscribe to new check-ins for their live session in real time.
alter publication supabase_realtime add table public.attendance_records;

-- Seed data ------------------------------------------------------------------
-- One sample building/room/course so the Attendance flow can be tested
-- end-to-end today, without an admin CRUD screen for these yet. Replace the
-- placeholder lat/long with your actual room's coordinates when known.
-- Re-runnable: guarded by existence checks and ON CONFLICT DO NOTHING.
do $$
declare
  v_building_id uuid;
  v_facility_id uuid;
  v_course_id uuid;
begin
  select id into v_building_id from public.buildings where building_name = 'Block A';
  if v_building_id is null then
    insert into public.buildings (building_name, total_floors)
    values ('Block A', 5)
    returning id into v_building_id;
  end if;

  select id into v_facility_id from public.facilities where room_name = 'A-501';
  if v_facility_id is null then
    insert into public.facilities (building_id, room_name, type, status, latitude, longitude, radius_meters)
    values (v_building_id, 'A-501', 'lecture_hall', 'available', 3.2159, 101.7284, 50)
    returning id into v_facility_id;
  end if;

  select id into v_course_id from public.courses where course_code = 'BACS2003';
  if v_course_id is null then
    insert into public.courses (course_code, course_name)
    values ('BACS2003', 'Software Engineering')
    returning id into v_course_id;
  end if;

  insert into public.course_enrollments (student_id, course_id)
  select p.id, v_course_id
  from public.profiles p
  where p.role = 'student'
  on conflict (student_id, course_id) do nothing;
end $$;
