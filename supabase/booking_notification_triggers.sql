-- Two booking-reminder cron triggers, filling the gap noted in
-- notification_triggers.sql: 'booking' was already a valid notification
-- type and allow_booking_reminders already existed as a preference toggle,
-- but no check function ever populated it. Mirrors the existing parking
-- pair (check_parking_ending_soon / check_parking_duration_exceeded)
-- exactly, adapted for bookings.booking_date + start_time/end_time being
-- stored as a date plus "hh:mm AM/PM" text rather than timestamptz — the
-- same to_timestamp(..., 'HH12:MI AM')::time conversion create_booking's
-- own overlap check already uses.
--
-- Run this in the Supabase SQL editor AFTER notification_triggers.sql and
-- booking_schema.sql.

-- Booking ending soon (~15 minutes before end) -------------------------------
-- CONFIRMED/CHECKED IN only — CHECKED OUT already left, CANCELLED/NO SHOW
-- never happened, neither needs an "ending soon" nudge.
create or replace function public.check_booking_ending_soon() returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_now_myt timestamp := (now() at time zone 'Asia/Kuala_Lumpur');
begin
  for r in
    select b.id, b.user_id, f.room_name
    from public.bookings b
    join public.facilities f on f.id = b.facility_id
    where b.status in ('CONFIRMED', 'CHECKED IN')
      and (b.booking_date + to_timestamp(b.end_time, 'HH12:MI AM')::time)
            between v_now_myt and (v_now_myt + interval '15 minutes')
  loop
    perform public.notify_user(
      r.user_id,
      'Booking ending soon',
      'Your booking for ' || r.room_name || ' ends in 15 minutes.',
      'booking',
      'booking_ending:' || r.id
    );
  end loop;
end;
$$;

-- Booking time passed ---------------------------------------------------------
-- Fires once end_time has passed, regardless of whether the booking was
-- ever checked in — CONFIRMED (never checked in), CHECKED IN, and CHECKED
-- OUT all still get told their slot's time is over. CANCELLED/NO SHOW are
-- excluded, same reasoning as above. dedupe_key is per-booking only (no
-- date suffix, unlike parking's overstay check) since a booking's end
-- time only ever passes once — no daily re-nag needed.
create or replace function public.check_booking_time_passed() returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_now_myt timestamp := (now() at time zone 'Asia/Kuala_Lumpur');
begin
  for r in
    select b.id, b.user_id, f.room_name
    from public.bookings b
    join public.facilities f on f.id = b.facility_id
    where b.status in ('CONFIRMED', 'CHECKED IN', 'CHECKED OUT')
      and v_now_myt > (b.booking_date + to_timestamp(b.end_time, 'HH12:MI AM')::time)
  loop
    perform public.notify_user(
      r.user_id,
      'Booking time ended',
      'Your booking for ' || r.room_name || ' has ended.',
      'booking',
      'booking_ended:' || r.id
    );
  end loop;
end;
$$;

-- Schedules -----------------------------------------------------------------
-- Same 5-minute cadence as the other time-sensitive checks.
select cron.unschedule(jobid) from cron.job where jobname = 'check_booking_ending_soon';
select cron.schedule('check_booking_ending_soon', '*/5 * * * *', $$select public.check_booking_ending_soon()$$);

select cron.unschedule(jobid) from cron.job where jobname = 'check_booking_time_passed';
select cron.schedule('check_booking_time_passed', '*/5 * * * *', $$select public.check_booking_time_passed()$$);
