-- Cap active/upcoming reservations at 1 per student. Decided deliberately
-- (previously unbounded — a student could queue unlimited future
-- reservations across different slots): status = 'reserved' covers both
-- an already-started session and a not-yet-started booking, since
-- finish_parking_reservation/cancel_parking_reservation both move a row
-- out of 'reserved' — so this one check naturally means "active + upcoming
-- together" without needing to separately look at start_time.
--
-- Cancellation itself stays free (no penalty, no fee) — the cap above
-- already stops hoarding multiple slots at once, so giving one up is a
-- normal action. But nothing tracked how often a student cancelled, so a
-- book → cancel → book → cancel loop could run indefinitely (e.g. to keep
-- "reserving" a popular slot without ever actually using it). Below adds a
-- daily cap of 3 cancellations per student — generous enough for genuine
-- plan changes, low enough to stop that loop.
--
-- Run this in the Supabase SQL editor AFTER parking_schema.sql.

-- cancelled_at wasn't tracked at all before — needed to know whether a
-- cancellation happened "today" for the cap below.
alter table public.parking_reservations
  add column if not exists cancelled_at timestamptz;

-- The "1 active/upcoming reservation per user" rule was only a check inside
-- book_parking_slot — two concurrent calls (double-tap, retry, two devices)
-- could both pass it before either inserts. This partial unique index is
-- the actual backstop; book_parking_slot catches its violation below and
-- returns the same friendly message as the pre-check.
create unique index if not exists parking_reservations_one_active_per_user
  on public.parking_reservations (user_id)
  where status = 'reserved';

create or replace function public.book_parking_slot(
  p_slot_id uuid,
  p_plate_num text,
  p_start timestamptz,
  p_end timestamptz
)
returns jsonb
language plpgsql
security definer
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

  if exists (
    select 1 from public.parking_reservations
    where user_id = auth.uid() and status = 'reserved'
  ) then
    return jsonb_build_object(
      'success', false,
      'reason', 'You already have an active or upcoming reservation — finish or cancel it before booking another.'
    );
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
    when unique_violation then
      -- Lost the race against a concurrent booking by the same user — the
      -- parking_reservations_one_active_per_user partial index caught it.
      return jsonb_build_object(
        'success', false,
        'reason', 'You already have an active or upcoming reservation — finish or cancel it before booking another.'
      );
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

-- Same shape as the original in parking_schema.sql, plus the daily cap and
-- stamping cancelled_at (the original never set it — there was nothing to
-- count against before).
create or replace function public.cancel_parking_reservation(p_reservation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation record;
  v_cancels_today int;
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

  select count(*) into v_cancels_today
  from public.parking_reservations
  where user_id = auth.uid()
    and status = 'cancelled'
    and cancelled_at is not null
    and (cancelled_at at time zone 'Asia/Kuala_Lumpur')::date
        = (now() at time zone 'Asia/Kuala_Lumpur')::date;

  if v_cancels_today >= 3 then
    return jsonb_build_object(
      'success', false,
      'reason', 'You''ve reached today''s limit of 3 cancellations — try again tomorrow.'
    );
  end if;

  update public.parking_reservations
  set status = 'cancelled', cancelled_at = now()
  where id = p_reservation_id;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.cancel_parking_reservation(uuid) to authenticated;
