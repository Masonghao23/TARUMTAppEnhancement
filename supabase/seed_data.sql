-- Example test data for the Attendance module: a few buildings, rooms, and
-- courses beyond the single row created in attendance_schema.sql. Generic
-- placeholder names — edit freely once you have the real TARUMT list.
--
-- All rooms are seeded near the same coordinates already set on A-501 for
-- live testing, with a generous radius, so any of them work for check-in
-- regardless of which one a session uses. Adjust lat/long/radius per room
-- once you're testing from campus.
--
-- Idempotent: safe to re-run. Run this AFTER schema.sql and
-- attendance_schema.sql.

do $$
declare
  v_block_a uuid;
  v_block_b uuid;
  v_block_c uuid;
  v_test_lat double precision := 3.194667;
  v_test_long double precision := 101.634778;
  v_test_radius integer := 500;
begin
  -- Buildings ---------------------------------------------------------------
  select id into v_block_a from public.buildings where building_name = 'Block A';
  if v_block_a is null then
    insert into public.buildings (building_name, total_floors)
    values ('Block A', 5) returning id into v_block_a;
  end if;

  select id into v_block_b from public.buildings where building_name = 'Block B';
  if v_block_b is null then
    insert into public.buildings (building_name, total_floors)
    values ('Block B', 4) returning id into v_block_b;
  end if;

  select id into v_block_c from public.buildings where building_name = 'Block C';
  if v_block_c is null then
    insert into public.buildings (building_name, total_floors)
    values ('Block C', 6) returning id into v_block_c;
  end if;

  -- Facilities (rooms) --------------------------------------------------------
  if not exists (select 1 from public.facilities where room_name = 'A-502') then
    insert into public.facilities (building_id, room_name, type, status, latitude, longitude, radius_meters)
    values (v_block_a, 'A-502', 'computer_lab', 'available', v_test_lat, v_test_long, v_test_radius);
  end if;

  if not exists (select 1 from public.facilities where room_name = 'A-601') then
    insert into public.facilities (building_id, room_name, type, status, latitude, longitude, radius_meters)
    values (v_block_a, 'A-601', 'lecture_hall', 'available', v_test_lat, v_test_long, v_test_radius);
  end if;

  if not exists (select 1 from public.facilities where room_name = 'B-201') then
    insert into public.facilities (building_id, room_name, type, status, latitude, longitude, radius_meters)
    values (v_block_b, 'B-201', 'lecture_hall', 'available', v_test_lat, v_test_long, v_test_radius);
  end if;

  if not exists (select 1 from public.facilities where room_name = 'B-305') then
    insert into public.facilities (building_id, room_name, type, status, latitude, longitude, radius_meters)
    values (v_block_b, 'B-305', 'tutorial_room', 'available', v_test_lat, v_test_long, v_test_radius);
  end if;

  if not exists (select 1 from public.facilities where room_name = 'C-101') then
    insert into public.facilities (building_id, room_name, type, status, latitude, longitude, radius_meters)
    values (v_block_c, 'C-101', 'auditorium', 'available', v_test_lat, v_test_long, v_test_radius);
  end if;

  if not exists (select 1 from public.facilities where room_name = 'C-102') then
    insert into public.facilities (building_id, room_name, type, status, latitude, longitude, radius_meters)
    values (v_block_c, 'C-102', 'computer_lab', 'available', v_test_lat, v_test_long, v_test_radius);
  end if;

  -- Courses -------------------------------------------------------------------
  insert into public.courses (course_code, course_name) values
    ('BACS2013', 'Database Systems'),
    ('BACS3033', 'Mobile Application Development'),
    ('BIT2014', 'Data Structures and Algorithms'),
    ('BFIN1013', 'Principles of Finance'),
    ('BENG1013', 'Engineering Mathematics')
  on conflict (course_code) do nothing;

  -- Enroll every existing student in every course, so any student can be
  -- used to test check-in against any seeded course/session.
  insert into public.course_enrollments (student_id, course_id)
  select p.id, c.id
  from public.profiles p
  cross join public.courses c
  where p.role = 'student'
  on conflict (student_id, course_id) do nothing;
end $$;
