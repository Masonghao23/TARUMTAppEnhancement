-- Fixes process_nfc_checkin throwing P0003 ("query returned more than one
-- row") — two independent causes, both hit live:
--   1. 5 test profiles (Ma, Ong Kian Hang, Jack, Joker Ma, System Admin)
--      all had the same demo card's UID (D07C7E22) set by hand during
--      testing, since no app screen actually writes rfid_uid yet (only
--      ever read) — the SELECT INTO matched all 5.
--   2. Even after fixing that, Ma alone has 3 separate CONFIRMED bookings
--      for today — the UPDATE ... RETURNING id INTO (a scalar target) hit
--      all 3 rows at once, which is exactly as invalid as #1 was.
-- Fixed all of it:
--   - process_nfc_checkin's profile lookup takes LIMIT 1 defensively.
--   - Its booking update now targets exactly one row (by id, chosen as
--     today's earliest-starting CONFIRMED booking) via a subquery, instead
--     of an unscoped UPDATE that could touch several rows at once — this
--     was a real correctness bug too, not just a crash risk: as written,
--     scanning once would have silently marked every CONFIRMED booking
--     that day as CHECKED IN, not just the relevant one.
--   - A partial unique index stops rfid_uid duplicates from being created
--     again (NULL rfid_uid, the common case before a card is bound, stays
--     unrestricted).
--   - The 4 extra rfid_uid bindings are cleared, leaving only Ma's.

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
  select id, name into v_profile from public.profiles
  where rfid_uid = p_rfid_uid
  order by created_at
  limit 1;

  if not found then
    return jsonb_build_object(
      'success', false,
      'outcome', 'not_registered',
      'reason', 'Card not registered.'
    );
  end if;

  update public.bookings
  set status = 'CHECKED IN'
  where id = (
    select id from public.bookings
    where user_id = v_profile.id
      and booking_date = current_date
      and status = 'CONFIRMED'
    order by to_timestamp(start_time, 'HH12:MI AM')::time
    limit 1
  )
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

-- Must run before the unique index below — can't index a column that
-- still has duplicate values.
update public.profiles
set rfid_uid = null
where rfid_uid = 'D07C7E22'
  and id <> '8c5bdfb0-85db-4686-a4f3-91bfd03b8745'; -- Ma keeps the card

create unique index if not exists profiles_rfid_uid_unique_idx
  on public.profiles (rfid_uid)
  where rfid_uid is not null;
