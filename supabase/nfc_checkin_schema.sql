-- NFC Check-in Demo — ported from tarumt_app's demo_checkin_screen.dart.
--
-- Run this in the Supabase SQL editor AFTER booking_schema.sql (it updates
-- public.bookings and reads public.profiles.rfid_uid, an existing column
-- schema.sql already reserved for this — see the "whitelists editable
-- columns (name, rfid_uid)" comment near its profiles grants).
--
-- One deliberate departure from the original: the old screen's
-- _processCheckIn() ran two *raw, unguarded* Supabase client calls
-- (a `students` select by rfid_tag, then a `bookings` update) straight from
-- the app — exploitable as-is here, since this app's `bookings` table has
-- no UPDATE policy at all (every other mutation already goes through a
-- security-definer RPC; opening a raw update policy for this one screen
-- would let any authenticated user flip the status of anyone else's
-- booking by guessing/observing a booking id). Moved server-side instead;
-- the scanning UI, messages, and 3-way outcome (not registered / no
-- booking today / checked in) are byte-for-byte the same as the original.

create or replace function public.process_nfc_checkin(p_rfid_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile record;
  v_checked_in_id uuid;
begin
  select id, name into v_profile from public.profiles where rfid_uid = p_rfid_uid;
  if not found then
    return jsonb_build_object(
      'success', false,
      'outcome', 'not_registered',
      'reason', 'Card not registered.'
    );
  end if;

  update public.bookings
  set status = 'CHECKED IN'
  where user_id = v_profile.id
    and booking_date = current_date
    and status = 'CONFIRMED'
  returning id into v_checked_in_id;

  if v_checked_in_id is null then
    return jsonb_build_object(
      'success', false,
      'outcome', 'no_booking',
      'reason', 'No active booking found for ' || v_profile.name || ' today.',
      'studentName', v_profile.name
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'outcome', 'checked_in',
    'reason', 'Welcome ' || v_profile.name || '! Checked in successfully.',
    'studentName', v_profile.name
  );
end;
$$;

grant execute on function public.process_nfc_checkin(text) to authenticated;
