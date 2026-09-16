-- Adds buildings DK AB and Block D (Arena already existed), plus their
-- rooms, requested 2026-09-16. Idempotent — matches the pattern in
-- booking_migration_schema.sql / seed_data.sql, safe to re-run.
--
-- Note: latitude/longitude are left null for the new rooms below (real
-- coordinates weren't supplied) — same call made for the bookable
-- Discussion Rooms in booking_migration_schema.sql. That's fine for
-- Booking display, but if these rooms are later used for attendance
-- sessions, GPS-based check-in geofencing won't work for them until real
-- coordinates are filled in.
do $$
declare
  v_dkab_id uuid;
  v_blockd_id uuid;
  v_arena_id uuid;
begin
  -- Buildings --------------------------------------------------------------
  select id into v_dkab_id from public.buildings where building_name = 'DK AB';
  if v_dkab_id is null then
    insert into public.buildings (building_name)
    values ('DK AB')
    returning id into v_dkab_id;
  end if;

  select id into v_blockd_id from public.buildings where building_name = 'Block D';
  if v_blockd_id is null then
    insert into public.buildings (building_name)
    values ('Block D')
    returning id into v_blockd_id;
  end if;

  select id into v_arena_id from public.buildings where building_name = 'Arena';

  -- Facilities ---------------------------------------------------------------
  -- DK AB: ABA, ABB (lecture_hall)
  if not exists (select 1 from public.facilities where room_name = 'ABA' and building_id = v_dkab_id) then
    insert into public.facilities (building_id, room_name, type)
    values (v_dkab_id, 'ABA', 'lecture_hall');
  end if;
  if not exists (select 1 from public.facilities where room_name = 'ABB' and building_id = v_dkab_id) then
    insert into public.facilities (building_id, room_name, type)
    values (v_dkab_id, 'ABB', 'lecture_hall');
  end if;

  -- Arena: TA210, TA220 (tutorial_room)
  if not exists (select 1 from public.facilities where room_name = 'TA210' and building_id = v_arena_id) then
    insert into public.facilities (building_id, room_name, type)
    values (v_arena_id, 'TA210', 'tutorial_room');
  end if;
  if not exists (select 1 from public.facilities where room_name = 'TA220' and building_id = v_arena_id) then
    insert into public.facilities (building_id, room_name, type)
    values (v_arena_id, 'TA220', 'tutorial_room');
  end if;

  -- Block D: D303, D203 (computer_lab)
  if not exists (select 1 from public.facilities where room_name = 'D303' and building_id = v_blockd_id) then
    insert into public.facilities (building_id, room_name, type)
    values (v_blockd_id, 'D303', 'computer_lab');
  end if;
  if not exists (select 1 from public.facilities where room_name = 'D203' and building_id = v_blockd_id) then
    insert into public.facilities (building_id, room_name, type)
    values (v_blockd_id, 'D203', 'computer_lab');
  end if;
end $$;
