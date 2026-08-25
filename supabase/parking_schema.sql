-- Car Parking Module schema — mirrors the ERD (Figure 4.9) and Class Diagram
-- (Figure 4.10/4.11) in the Project I report: ParkingSlot, ParkingReservation,
-- RegisteredVehicle. parking_slots/parking_reservations/registered_vehicles
-- already exist as structure-only stubs from future_modules_schema.sql (RLS
-- enabled, zero policies) — this file adds the columns/functions/policies
-- needed to make the module actually work, and is additive-only (no drops).
--
-- Run this in the Supabase SQL editor AFTER schema.sql and
-- future_modules_schema.sql.
--
-- Design notes:
--   1. parking_slots.status (existing column) is left as inert/legacy —
--      real occupancy is always computed live from parking_reservations for
--      the queried time window via get_parking_slots(), so there is no
--      cached column that can drift out of sync.
--   2. is_reservable is a separate staff-controlled override (FR08),
--      independent of occupancy — matches the class diagram's
--      setReservableState(isReservable, staffId) being distinct from
--      updateStatus(newStatus).
--   3. Payment is simulated (no real gateway available for this project) —
--      book_parking_slot()/extend_parking_reservation() "process payment"
--      instantly and always succeed, generating a mock transaction_ref, in
--      the same spirit as the already-simulated RFID/parking hardware.
--   4. Double-booking is prevented at the DB level with an exclusion
--      constraint (not just an application-level check-then-insert, which
--      would race) — needs btree_gist for the uuid equality term.

create extension if not exists btree_gist;

-- Parking operates 6:00 AM to 12:00 AM (midnight) local campus time —
-- shared by book/extend so neither a booking nor an extension can ever
-- cross into the next calendar day. Returns the instant of the next local
-- midnight after p_moment.
create or replace function public.parking_local_midnight(p_moment timestamptz)
returns timestamptz
language sql
immutable
as $$
  select (date_trunc('day', p_moment at time zone 'Asia/Kuala_Lumpur') + interval '1 day')
    at time zone 'Asia/Kuala_Lumpur';
$$;

-- parking_slots additions --------------------------------------------------
alter table public.parking_slots
  add column if not exists slot_number text,
  add column if not exists pos_x double precision not null default 0,
  add column if not exists pos_y double precision not null default 0,
  add column if not exists is_reservable boolean not null default true,
  add column if not exists is_reservable_updated_by uuid references public.profiles (id),
  add column if not exists is_reservable_updated_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'parking_slots_slot_number_key'
  ) then
    alter table public.parking_slots
      add constraint parking_slots_slot_number_key unique (slot_number);
  end if;
end $$;

-- parking_reservations additions -------------------------------------------
alter table public.parking_reservations
  add column if not exists transaction_ref text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'parking_reservations_status_check'
  ) then
    alter table public.parking_reservations
      add constraint parking_reservations_status_check
      check (status in ('reserved', 'completed', 'cancelled'));
  end if;
end $$;

-- Prevents two overlapping 'reserved' rows on the same slot at the DB level
-- (the use case explicitly worries about a slot "reserved by other in the
-- last few seconds" — a check-then-insert in application code alone has a
-- race window; this closes it regardless of caller).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'parking_reservations_no_overlap'
  ) then
    alter table public.parking_reservations
      add constraint parking_reservations_no_overlap
      exclude using gist (
        slot_id with =,
        tstzrange(start_time, end_time) with &&
      ) where (status = 'reserved');
  end if;
end $$;

create index if not exists parking_reservations_slot_time_idx
  on public.parking_reservations (slot_id, start_time, end_time);

-- registered_vehicles: no policies/grants existed yet -----------------------
grant select, insert, update, delete on public.registered_vehicles to authenticated;

drop policy if exists "registered_vehicles_own" on public.registered_vehicles;
create policy "registered_vehicles_own" on public.registered_vehicles
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- parking_slots: everyone can view the floor plan ---------------------------
grant select on public.parking_slots to authenticated;

drop policy if exists "parking_slots_select_all" on public.parking_slots;
create policy "parking_slots_select_all" on public.parking_slots
  for select using (true);

-- parking_reservations: own rows or staff/admin, writes only via functions --
grant select on public.parking_reservations to authenticated;

drop policy if exists "parking_reservations_select_own_or_staff" on public.parking_reservations;
create policy "parking_reservations_select_own_or_staff" on public.parking_reservations
  for select using (
    auth.uid() = user_id
    or public.current_user_role() in ('staff', 'admin')
  );

-- Single editable spot for the flat hourly rate (RM2.00/hour placeholder,
-- matches the report mockup's "RM3 for 2 hrs" example scaled to a round
-- number) — change this one function when the real rate is known.
create or replace function public.parking_rate_per_hour()
returns numeric
language sql
immutable
as $$
  select 2.00::numeric;
$$;

create or replace function public.calculate_parking_fee(p_duration_seconds integer)
returns numeric
language sql
immutable
as $$
  select round((p_duration_seconds / 3600.0) * public.parking_rate_per_hour(), 2);
$$;

grant execute on function public.calculate_parking_fee(integer) to authenticated;

-- Live occupancy for every slot over a given window (defaults to "right
-- now" for the dashboard; also reused by the booking screen to check
-- availability for a future date/time range per the use case's step
-- "System queries database for all existing reservations within that
-- specific time duration"). Never trusts a cached status column.
create or replace function public.get_parking_slots(
  p_start timestamptz default now(),
  p_end timestamptz default now()
)
returns table (
  id uuid,
  slot_number text,
  pos_x double precision,
  pos_y double precision,
  is_reservable boolean,
  is_occupied boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id,
    s.slot_number,
    s.pos_x,
    s.pos_y,
    s.is_reservable,
    exists (
      select 1 from public.parking_reservations r
      where r.slot_id = s.id
        and r.status = 'reserved'
        -- tstzrange() with equal bounds is an *empty* range that can never
        -- overlap anything — callers checking "right now" (the common case,
        -- via the p_start/p_end defaults) naturally pass p_start = p_end,
        -- so nudge the upper bound forward by an instant to keep the same
        -- half-open [start,end) convention as reservations without ever
        -- degenerating to empty.
        and tstzrange(r.start_time, r.end_time) && tstzrange(
          p_start,
          case when p_end > p_start then p_end else p_start + interval '1 microsecond' end
        )
    ) as is_occupied
  from public.parking_slots s
  order by s.pos_y, s.pos_x;
$$;

grant execute on function public.get_parking_slots(timestamptz, timestamptz) to authenticated;

-- Books a slot for [p_start, p_end), simulates payment (always succeeds),
-- and records the reservation — all atomically in one call so the
-- check-availability-then-insert cannot race across two callers (and the
-- exclusion constraint above is the hard backstop if it somehow does).
create or replace function public.book_parking_slot(
  p_slot_id uuid,
  p_plate_num text,
  p_start timestamptz,
  p_end timestamptz
)
returns jsonb
language plpgsql
security definer
-- pgcrypto (gen_random_bytes()) lives in the `extensions` schema on
-- Supabase projects, not `public` — see attendance_schema.sql's
-- submit_attendance() for the same gotcha.
set search_path = public, extensions
as $$
declare
  v_slot record;
  v_fee numeric;
  v_txn text;
  v_reservation_id uuid;
begin
  if p_end <= p_start then
    return jsonb_build_object('success', false, 'reason', 'End time must be after start time.');
  end if;

  -- Bookings are made at least 1 day ahead — today's dashboard is
  -- view-only, since a same-day arrival just self-parks in whatever's
  -- open rather than reserving a specific slot. Must use the same local
  -- (Malaysia) day boundary as the operating-hours checks below, not a
  -- UTC one — otherwise a valid early-morning local booking can fall on
  -- the wrong side of a UTC midnight that doesn't line up with it.
  if p_start < public.parking_local_midnight(now()) then
    return jsonb_build_object(
      'success', false,
      'reason', 'Parking must be reserved at least 1 day in advance.'
    );
  end if;

  -- Parking is only available 6:00 AM to 12:00 AM (midnight) local time —
  -- the start must fall in that window and the session cannot cross into
  -- the next day.
  if extract(hour from (p_start at time zone 'Asia/Kuala_Lumpur')) < 6 then
    return jsonb_build_object(
      'success', false,
      'reason', 'Parking is only available from 6:00 AM to 12:00 AM.'
    );
  end if;
  if p_end > public.parking_local_midnight(p_start) then
    return jsonb_build_object(
      'success', false,
      'reason', 'Booking cannot extend past 12:00 AM — pick a shorter duration or an earlier start time.'
    );
  end if;

  select * into v_slot from public.parking_slots where id = p_slot_id;
  if not found then
    return jsonb_build_object('success', false, 'reason', 'Parking slot not found.');
  end if;
  if not v_slot.is_reservable then
    return jsonb_build_object('success', false, 'reason', 'This slot is not available for reservation.');
  end if;

  if not exists (
    select 1 from public.registered_vehicles
    where plate_num = p_plate_num and user_id = auth.uid()
  ) then
    return jsonb_build_object('success', false, 'reason', 'That vehicle is not registered to your account.');
  end if;

  if exists (
    select 1 from public.parking_reservations
    where slot_id = p_slot_id
      and status = 'reserved'
      and tstzrange(start_time, end_time) && tstzrange(p_start, p_end)
  ) then
    return jsonb_build_object('success', false, 'reason', 'The parking slot is no longer available.');
  end if;

  v_fee := public.calculate_parking_fee(extract(epoch from (p_end - p_start))::integer);

  -- Simulated payment gateway call — always succeeds (no real gateway
  -- available for this project); a real integration would replace this
  -- block with an actual charge and only proceed on success.
  v_txn := 'MOCK-' || encode(gen_random_bytes(6), 'hex');

  begin
    insert into public.parking_reservations
      (user_id, slot_id, plate_num, start_time, end_time, total_fee, status, transaction_ref)
    values
      (auth.uid(), p_slot_id, p_plate_num, p_start, p_end, v_fee, 'reserved', v_txn)
    returning id into v_reservation_id;
  exception
    when exclusion_violation then
      return jsonb_build_object('success', false, 'reason', 'The parking slot is no longer available.');
  end;

  return jsonb_build_object(
    'success', true,
    'reservationId', v_reservation_id,
    'fee', v_fee,
    'transactionRef', v_txn
  );
end;
$$;

grant execute on function public.book_parking_slot(uuid, text, timestamptz, timestamptz) to authenticated;

-- Extends an active reservation's end time, simulating an additional
-- payment for the extra duration.
create or replace function public.extend_parking_reservation(
  p_reservation_id uuid,
  p_additional_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_reservation record;
  v_new_end timestamptz;
  v_fee numeric;
  v_txn text;
begin
  select * into v_reservation
  from public.parking_reservations
  where id = p_reservation_id and user_id = auth.uid();

  if not found then
    return jsonb_build_object('success', false, 'reason', 'Reservation not found.');
  end if;
  if v_reservation.status <> 'reserved' then
    return jsonb_build_object('success', false, 'reason', 'This session has already ended.');
  end if;

  v_new_end := v_reservation.end_time + make_interval(secs => p_additional_seconds);

  -- Same 6:00 AM-12:00 AM operating window as booking — an extension can
  -- never push the session past midnight of the day it started.
  if v_new_end > public.parking_local_midnight(v_reservation.start_time) then
    return jsonb_build_object(
      'success', false,
      'reason', 'Extending would go past 12:00 AM — parking is only available until midnight.'
    );
  end if;

  if exists (
    select 1 from public.parking_reservations
    where slot_id = v_reservation.slot_id
      and status = 'reserved'
      and id <> v_reservation.id
      and tstzrange(start_time, end_time) && tstzrange(v_reservation.end_time, v_new_end)
  ) then
    return jsonb_build_object(
      'success', false,
      'reason', 'Selected additional time extension conflicts with future reserved time.'
    );
  end if;

  v_fee := public.calculate_parking_fee(p_additional_seconds);
  v_txn := 'MOCK-' || encode(gen_random_bytes(6), 'hex');

  begin
    update public.parking_reservations
    set end_time = v_new_end,
        total_fee = total_fee + v_fee,
        transaction_ref = v_txn
    where id = p_reservation_id;
  exception
    when exclusion_violation then
      return jsonb_build_object(
        'success', false,
        'reason', 'Selected additional time extension conflicts with future reserved time.'
      );
  end;

  return jsonb_build_object(
    'success', true,
    'newEndTime', v_new_end,
    'additionalFee', v_fee,
    'transactionRef', v_txn
  );
end;
$$;

grant execute on function public.extend_parking_reservation(uuid, integer) to authenticated;

-- Ends an active session early (the mockup's "Finish" button).
create or replace function public.finish_parking_reservation(p_reservation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.parking_reservations
  set status = 'completed',
      end_time = least(end_time, now())
  where id = p_reservation_id and user_id = auth.uid() and status = 'reserved';

  if not found then
    return jsonb_build_object('success', false, 'reason', 'Reservation not found or already ended.');
  end if;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.finish_parking_reservation(uuid) to authenticated;

-- Cancels a future (not yet started) reservation.
create or replace function public.cancel_parking_reservation(p_reservation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation record;
begin
  select * into v_reservation
  from public.parking_reservations
  where id = p_reservation_id and user_id = auth.uid();

  if not found then
    return jsonb_build_object('success', false, 'reason', 'Reservation not found.');
  end if;
  if v_reservation.status <> 'reserved' then
    return jsonb_build_object('success', false, 'reason', 'This reservation cannot be cancelled.');
  end if;
  if v_reservation.start_time <= now() then
    return jsonb_build_object('success', false, 'reason', 'An active session cannot be cancelled — use Finish instead.');
  end if;

  update public.parking_reservations set status = 'cancelled' where id = p_reservation_id;
  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.cancel_parking_reservation(uuid) to authenticated;

-- FR08: academic staff can mark specific slots as non-reservable.
create or replace function public.set_parking_slot_reservable(
  p_slot_id uuid,
  p_is_reservable boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_user_role() not in ('staff', 'admin') then
    return jsonb_build_object('success', false, 'reason', 'Only staff can change slot availability.');
  end if;

  update public.parking_slots
  set is_reservable = p_is_reservable,
      is_reservable_updated_by = auth.uid(),
      is_reservable_updated_at = now()
  where id = p_slot_id;

  if not found then
    return jsonb_build_object('success', false, 'reason', 'Parking slot not found.');
  end if;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.set_parking_slot_reservable(uuid, boolean) to authenticated;

-- A student's own current/past reservations, with slot label for display.
create or replace function public.get_my_parking_reservations()
returns table (
  id uuid,
  slot_id uuid,
  slot_number text,
  plate_num text,
  start_time timestamptz,
  end_time timestamptz,
  total_fee numeric,
  status text,
  transaction_ref text
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.slot_id, s.slot_number, r.plate_num, r.start_time, r.end_time,
         r.total_fee, r.status, r.transaction_ref
  from public.parking_reservations r
  join public.parking_slots s on s.id = r.slot_id
  where r.user_id = auth.uid()
  order by r.start_time desc;
$$;

grant execute on function public.get_my_parking_reservations() to authenticated;

-- Let the live dashboard subscribe to reservation changes in real time
-- (NFR2: parking availability shall update within 5 seconds).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'parking_reservations'
  ) then
    alter publication supabase_realtime add table public.parking_reservations;
  end if;
end $$;

-- Seed data ------------------------------------------------------------------
-- Ground-floor layout derived from the real floor plan: a main hall of rows
-- A-G that tapers near the curved top-left wall (fewer/inset slots in the
-- top rows, full-width lower down), plus a secondary wing (rows H, J) set
-- off to the right with a gap standing in for the corridor between them.
-- pos_x/pos_y are grid cells consumed as-is by ParkingFloorMap — unused
-- cells (the inset on tapered rows, the corridor gap before the wing) are
-- simply left blank, which is how the curved/offset shape reads visually
-- without the widget needing to know about walls at all.
--
-- Replaces the previous 4x5 placeholder grid wholesale — deleting a slot
-- cascades to its reservations (parking_reservations.slot_id), which is
-- fine here since this project has no production booking data yet.
delete from public.parking_slots;

do $$
declare
  v_rows jsonb := '[
    {"label": "A", "y": 1, "x_start": 6,  "count": 6},
    {"label": "B", "y": 2, "x_start": 4,  "count": 8},
    {"label": "C", "y": 3, "x_start": 2,  "count": 10},
    {"label": "D", "y": 4, "x_start": 1,  "count": 11},
    {"label": "E", "y": 5, "x_start": 1,  "count": 11},
    {"label": "F", "y": 6, "x_start": 2,  "count": 10},
    {"label": "G", "y": 7, "x_start": 2,  "count": 10},
    {"label": "H", "y": 5, "x_start": 15, "count": 9},
    {"label": "J", "y": 6, "x_start": 15, "count": 9}
  ]'::jsonb;
  v_row jsonb;
  v_i int;
begin
  for v_row in select * from jsonb_array_elements(v_rows) loop
    for v_i in 1..(v_row ->> 'count')::int loop
      insert into public.parking_slots (slot_number, pos_x, pos_y, is_reservable)
      values (
        (v_row ->> 'label') || lpad(v_i::text, 2, '0'),
        (v_row ->> 'x_start')::int + v_i - 1,
        (v_row ->> 'y')::int,
        true
      );
    end loop;
  end loop;
end $$;
