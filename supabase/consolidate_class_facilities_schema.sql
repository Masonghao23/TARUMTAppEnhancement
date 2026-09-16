-- Consolidates every room reference from the old ad-hoc classroom
-- facilities (A-501/502/601, B-201/305, C-101/102, Arena Tutorial Room)
-- onto the 6 newly added facilities (ABA/ABB in DK AB, TA210/TA220 in
-- Arena, D303/D203 in Block D), requested 2026-09-16. Booking-only
-- Discussion Rooms (Arena/Cyber Centre/Library) are untouched — they were
-- never used for classes.
--
-- Every table with a facilities FK was checked, not just class_schedule:
-- class_schedule, class_schedule_exceptions, class_sessions (live/past
-- QR attendance sessions — ON DELETE RESTRICT, so leaving these
-- unmigrated would make the final delete fail outright) and
-- reschedule_requests all had real rows pointing at these old rooms.
-- bookings/access_logs did not (they only ever pointed at the bookable
-- Discussion Rooms), so they're left alone.
--
-- Mapping (old room -> new room), balanced by total references across
-- all four tables above:
--   A-601 (lecture_hall)                 -> ABA
--   A-501 (lecture_hall)                 -> ABA
--   B-201 (lecture_hall)                 -> ABB
--   C-101 (auditorium)                   -> ABB
--   Arena Tutorial Room (tutorial_room)  -> TA210
--   B-305 (tutorial_room)                -> TA220
--   A-502 (computer_lab)                 -> D303
--   C-102 (computer_lab)                 -> D203
--
-- Coordinates: the old data only ever used two distinct lat/long pairs
-- across every facility - (3.194667, 101.634778), the "main campus"
-- cluster used by most Block A/B/C rooms, and (3.2160788, 101.7288917),
-- already used by the existing Arena Tutorial Room. New rooms inherit
-- whichever cluster their own building already used: Arena keeps its own
-- existing coordinate; DK AB and Block D get the main-campus cluster
-- (the majority origin of the rooms feeding into them). These are real
-- previous values, not fabricated ones, but were not resurveyed for the
-- new buildings specifically - replace if better coordinates are known.
--
-- Idempotent: safe to re-run. On a second run the old-room lookups below
-- resolve to null (already deleted), and null-keyed updates/deletes are
-- harmless no-ops.
do $$
declare
  v_aba uuid; v_abb uuid; v_ta210 uuid; v_ta220 uuid; v_d303 uuid; v_d203 uuid;
  v_a501 uuid; v_a502 uuid; v_a601 uuid; v_b201 uuid; v_b305 uuid;
  v_c101 uuid; v_c102 uuid; v_arena_tut uuid;
  v_dkab_id uuid; v_arena_id uuid; v_blockd_id uuid;
begin
  select id into v_dkab_id from public.buildings where building_name = 'DK AB';
  select id into v_arena_id from public.buildings where building_name = 'Arena';
  select id into v_blockd_id from public.buildings where building_name = 'Block D';

  select id into v_aba from public.facilities where room_name = 'ABA' and building_id = v_dkab_id;
  select id into v_abb from public.facilities where room_name = 'ABB' and building_id = v_dkab_id;
  select id into v_ta210 from public.facilities where room_name = 'TA210' and building_id = v_arena_id;
  select id into v_ta220 from public.facilities where room_name = 'TA220' and building_id = v_arena_id;
  select id into v_d303 from public.facilities where room_name = 'D303' and building_id = v_blockd_id;
  select id into v_d203 from public.facilities where room_name = 'D203' and building_id = v_blockd_id;

  select id into v_a501 from public.facilities where room_name = 'A-501';
  select id into v_a502 from public.facilities where room_name = 'A-502';
  select id into v_a601 from public.facilities where room_name = 'A-601';
  select id into v_b201 from public.facilities where room_name = 'B-201';
  select id into v_b305 from public.facilities where room_name = 'B-305';
  select id into v_c101 from public.facilities where room_name = 'C-101';
  select id into v_c102 from public.facilities where room_name = 'C-102';
  select id into v_arena_tut from public.facilities where room_name = 'Arena Tutorial Room';

  -- Coordinates for the new rooms -------------------------------------------
  update public.facilities set latitude = 3.194667, longitude = 101.634778
    where id in (v_aba, v_abb, v_d303, v_d203);
  update public.facilities set latitude = 3.2160788, longitude = 101.7288917
    where id in (v_ta210, v_ta220);

  -- class_schedule reassignment ---------------------------------------------
  update public.class_schedule set room_id = v_aba where room_id = v_a601;
  update public.class_schedule set room_id = v_aba where room_id = v_a501;
  update public.class_schedule set room_id = v_abb where room_id = v_b201;
  update public.class_schedule set room_id = v_abb where room_id = v_c101;
  update public.class_schedule set room_id = v_ta210 where room_id = v_arena_tut;
  update public.class_schedule set room_id = v_ta220 where room_id = v_b305;
  update public.class_schedule set room_id = v_d303 where room_id = v_a502;
  update public.class_schedule set room_id = v_d203 where room_id = v_c102;

  -- class_schedule_exceptions reassignment -----------------------------------
  update public.class_schedule_exceptions set room_id = v_ta210 where room_id = v_arena_tut;
  update public.class_schedule_exceptions set room_id = v_ta220 where room_id = v_b305;

  -- class_sessions reassignment (ON DELETE RESTRICT — must be migrated
  -- before the delete below, or it fails outright) ---------------------------
  update public.class_sessions set room_id = v_aba where room_id = v_a601;
  update public.class_sessions set room_id = v_aba where room_id = v_a501;
  update public.class_sessions set room_id = v_abb where room_id = v_b201;
  update public.class_sessions set room_id = v_abb where room_id = v_c101;
  update public.class_sessions set room_id = v_ta210 where room_id = v_arena_tut;
  update public.class_sessions set room_id = v_ta220 where room_id = v_b305;
  update public.class_sessions set room_id = v_d303 where room_id = v_a502;
  update public.class_sessions set room_id = v_d203 where room_id = v_c102;

  -- reschedule_requests reassignment ------------------------------------------
  update public.reschedule_requests set room_id = v_aba where room_id = v_a601;
  update public.reschedule_requests set room_id = v_aba where room_id = v_a501;
  update public.reschedule_requests set room_id = v_abb where room_id = v_b201;
  update public.reschedule_requests set room_id = v_abb where room_id = v_c101;
  update public.reschedule_requests set room_id = v_ta210 where room_id = v_arena_tut;
  update public.reschedule_requests set room_id = v_ta220 where room_id = v_b305;
  update public.reschedule_requests set room_id = v_d303 where room_id = v_a502;
  update public.reschedule_requests set room_id = v_d203 where room_id = v_c102;

  -- Remove the old classroom facilities (booking-only Discussion Rooms
  -- are not touched) — safe now that nothing references them.
  delete from public.facilities
    where id in (v_a501, v_a502, v_a601, v_b201, v_b305, v_c101, v_c102, v_arena_tut);
end $$;
