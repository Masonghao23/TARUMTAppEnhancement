-- Booking module — RLS + RPCs, ported from tarumt_app's Facility Booking
-- and My Bookings screens onto the schema booking_migration_schema.sql
-- already prepared (facilities/buildings reused, bookings restructured).
--
-- Run this in the Supabase SQL editor AFTER booking_migration_schema.sql.
--
-- Departures from the old system, all deliberate:
--   - auth.uid() identifies the booking owner instead of the old screen's
--     hardcoded demo student ('24WMR07987') — the old app only ever had
--     one real user, so this never mattered there; here it must.
--   - Because there can now be more than one real user, double-booking the
--     same room/date/time (which the old app never guarded against, single
--     user) is checked server-side before insert — same reasoning as this
--     app's existing parking_reservations overlap guard.
--   - facilities/buildings already have public "select_all" policies from
--     attendance_schema.sql, so room listing needs no new RPC — the client
--     reads public.facilities/public.buildings directly.

alter table public.bookings enable row level security;

grant select on public.bookings to authenticated;

drop policy if exists "bookings_select_own_or_staff" on public.bookings;
create policy "bookings_select_own_or_staff" on public.bookings
  for select using (
    auth.uid() = user_id
    or public.current_user_role() in ('staff', 'admin')
  );

-- create_booking -------------------------------------------------------------
-- p_start_time/p_end_time are "hh:mm AM/PM" strings (e.g. "08:00 AM"), the
-- exact format the ported time-slot picker uses and the format already
-- locked into bookings.start_time/end_time by booking_migration_schema.sql.
create or replace function public.create_booking(
  p_facility_id uuid,
  p_booking_date date,
  p_start_time text,
  p_end_time text,
  p_pax integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_facility record;
  v_start time;
  v_end time;
  v_booking_id uuid;
begin
  if p_booking_date < current_date then
    return jsonb_build_object('success', false, 'reason', 'Booking date cannot be in the past.');
  end if;

  begin
    v_start := to_timestamp(p_start_time, 'HH12:MI AM')::time;
    v_end := to_timestamp(p_end_time, 'HH12:MI AM')::time;
  exception when others then
    return jsonb_build_object('success', false, 'reason', 'Invalid time format.');
  end;

  if v_end <= v_start then
    return jsonb_build_object('success', false, 'reason', 'End time must be after start time.');
  end if;

  select * into v_facility from public.facilities where id = p_facility_id;
  if not found then
    return jsonb_build_object('success', false, 'reason', 'Facility not found.');
  end if;
  if v_facility.status <> 'available' then
    return jsonb_build_object('success', false, 'reason', 'This facility is not available for booking.');
  end if;
  if p_pax is not null and v_facility.capacity is not null and p_pax > v_facility.capacity then
    return jsonb_build_object('success', false, 'reason', 'That many people won''t fit — capacity is ' || v_facility.capacity || '.');
  end if;

  if exists (
    select 1 from public.bookings b
    where b.facility_id = p_facility_id
      and b.booking_date = p_booking_date
      and b.status not in ('CANCELLED', 'NO SHOW')
      and to_timestamp(b.start_time, 'HH12:MI AM')::time < v_end
      and to_timestamp(b.end_time, 'HH12:MI AM')::time > v_start
  ) then
    return jsonb_build_object('success', false, 'reason', 'This room is already booked for part of that time.');
  end if;

  insert into public.bookings (user_id, facility_id, booking_date, start_time, end_time, pax, status)
  values (auth.uid(), p_facility_id, p_booking_date, p_start_time, p_end_time, p_pax, 'CONFIRMED')
  returning id into v_booking_id;

  return jsonb_build_object('success', true, 'bookingId', v_booking_id);
end;
$$;

grant execute on function public.create_booking(uuid, date, text, text, integer) to authenticated;

-- cancel_booking ---------------------------------------------------------
create or replace function public.cancel_booking(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking record;
begin
  select * into v_booking from public.bookings where id = p_booking_id;
  if not found then
    return jsonb_build_object('success', false, 'reason', 'Booking not found.');
  end if;
  if v_booking.user_id <> auth.uid() then
    return jsonb_build_object('success', false, 'reason', 'You can only cancel your own bookings.');
  end if;
  if v_booking.status in ('CHECKED IN', 'CHECKED OUT') then
    return jsonb_build_object('success', false, 'reason', 'This booking has already started and can no longer be cancelled.');
  end if;
  if v_booking.status = 'CANCELLED' then
    return jsonb_build_object('success', false, 'reason', 'This booking is already cancelled.');
  end if;

  update public.bookings set status = 'CANCELLED' where id = p_booking_id;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.cancel_booking(uuid) to authenticated;

-- get_my_bookings ---------------------------------------------------------
-- Denormalized the same way the old my_booking_screen.dart's Supabase
-- select did ('*, facilities(name, venue_type, buildings(name))'), but
-- against this app's actual facilities/buildings column names.
create or replace function public.get_my_bookings()
returns table (
  id uuid,
  facility_id uuid,
  room_name text,
  facility_type text,
  building_name text,
  booking_date date,
  start_time text,
  end_time text,
  pax integer,
  status text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.id, b.facility_id, f.room_name, f.type, bl.building_name,
    b.booking_date, b.start_time, b.end_time, b.pax, b.status, b.created_at
  from public.bookings b
  join public.facilities f on f.id = b.facility_id
  left join public.buildings bl on bl.id = f.building_id
  where b.user_id = auth.uid()
  order by b.booking_date desc, to_timestamp(b.start_time, 'HH12:MI AM')::time desc;
$$;

grant execute on function public.get_my_bookings() to authenticated;
