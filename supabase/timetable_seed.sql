-- Clash-free weekly timetable for the 6 courses that exist by the time
-- this runs (5 from seed_data.sql, plus BACS2003 Software Engineering from
-- attendance_schema.sql's own seed row) — each gets a Lecture (2h) +
-- Tutorial (1h) + Practical (2h) slot, spread Mon-Fri so a student
-- enrolled in all 6 (every student, per seed_data.sql) never has two
-- classes at once. Reuses the rooms already seeded in
-- seed_data.sql/parking's attendance rooms.
--
-- Also seeds one example "replacement class" exception (Mobile App Dev's
-- Wednesday tutorial moved to Thursday 1-2pm) — matches the approved
-- mockup, and exercises the move/exception path end-to-end.
--
-- Idempotent: safe to re-run. Run this AFTER schema.sql, attendance_schema.sql,
-- seed_data.sql, and timetable_schema.sql.

do $$
declare
  v_lecturer uuid;
  v_db uuid;   -- BACS2013 Database Systems
  v_mad uuid;  -- BACS3033 Mobile Application Development
  v_dsa uuid;  -- BIT2014 Data Structures and Algorithms
  v_fin uuid;  -- BFIN1013 Principles of Finance
  v_eng uuid;  -- BENG1013 Engineering Mathematics
  v_se uuid;   -- BACS2003 Software Engineering (seeded by attendance_schema.sql)
  v_a601 uuid;
  v_b305 uuid;
  v_a502 uuid;
  v_b201 uuid;
  v_arena uuid;
  v_c102 uuid;
  v_c101 uuid;
  v_mad_tutorial_schedule uuid;
begin
  select id into v_lecturer from public.profiles where role in ('staff', 'admin') order by created_at limit 1;
  if v_lecturer is null then
    raise notice 'No staff/admin profile found — skipping timetable seed (create a staff account first).';
    return;
  end if;

  select id into v_db from public.courses where course_code = 'BACS2013';
  select id into v_mad from public.courses where course_code = 'BACS3033';
  select id into v_dsa from public.courses where course_code = 'BIT2014';
  select id into v_fin from public.courses where course_code = 'BFIN1013';
  select id into v_eng from public.courses where course_code = 'BENG1013';
  select id into v_se from public.courses where course_code = 'BACS2003';

  select id into v_a601 from public.facilities where room_name = 'A-601';
  select id into v_b305 from public.facilities where room_name = 'B-305';
  select id into v_a502 from public.facilities where room_name = 'A-502';
  select id into v_b201 from public.facilities where room_name = 'B-201';
  select id into v_arena from public.facilities where room_name = 'Arena Tutorial Room';
  select id into v_c102 from public.facilities where room_name = 'C-102';
  select id into v_c101 from public.facilities where room_name = 'C-101';

  if v_db is null or v_mad is null or v_dsa is null or v_fin is null or v_eng is null or v_se is null
     or v_a601 is null or v_b305 is null or v_a502 is null or v_b201 is null
     or v_arena is null or v_c102 is null or v_c101 is null then
    raise notice 'Missing a required course/room — run seed_data.sql and the Arena facility insert first.';
    return;
  end if;

  -- Monday ----------------------------------------------------------------
  if not exists (select 1 from public.class_schedule where course_id = v_db and session_type = 'lecture') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_db, 'lecture', v_lecturer, v_a601, 1, '08:00', '10:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_db and session_type = 'tutorial') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_db, 'tutorial', v_lecturer, v_b305, 1, '10:00', '11:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_dsa and session_type = 'practical') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_dsa, 'practical', v_lecturer, v_a502, 1, '11:00', '13:00');
  end if;

  -- Tuesday -----------------------------------------------------------------
  if not exists (select 1 from public.class_schedule where course_id = v_mad and session_type = 'lecture') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_mad, 'lecture', v_lecturer, v_b201, 2, '08:00', '10:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_fin and session_type = 'tutorial') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_fin, 'tutorial', v_lecturer, v_arena, 2, '10:00', '11:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_db and session_type = 'practical') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_db, 'practical', v_lecturer, v_c102, 2, '11:00', '13:00');
  end if;

  -- Wednesday -----------------------------------------------------------------
  if not exists (select 1 from public.class_schedule where course_id = v_dsa and session_type = 'lecture') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_dsa, 'lecture', v_lecturer, v_c101, 3, '09:00', '11:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_mad and session_type = 'tutorial') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_mad, 'tutorial', v_lecturer, v_b305, 3, '11:00', '12:00')
    returning id into v_mad_tutorial_schedule;
  else
    select id into v_mad_tutorial_schedule from public.class_schedule
    where course_id = v_mad and session_type = 'tutorial';
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_fin and session_type = 'practical') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_fin, 'practical', v_lecturer, v_a502, 3, '14:00', '16:00');
  end if;

  -- Thursday -----------------------------------------------------------------
  if not exists (select 1 from public.class_schedule where course_id = v_fin and session_type = 'lecture') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_fin, 'lecture', v_lecturer, v_a601, 4, '08:00', '10:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_dsa and session_type = 'tutorial') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_dsa, 'tutorial', v_lecturer, v_arena, 4, '10:00', '11:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_mad and session_type = 'practical') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_mad, 'practical', v_lecturer, v_c102, 4, '11:00', '13:00');
  end if;

  -- Friday -----------------------------------------------------------------
  if not exists (select 1 from public.class_schedule where course_id = v_eng and session_type = 'lecture') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_eng, 'lecture', v_lecturer, v_b201, 5, '09:00', '11:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_eng and session_type = 'tutorial') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_eng, 'tutorial', v_lecturer, v_b305, 5, '11:00', '12:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_eng and session_type = 'practical') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_eng, 'practical', v_lecturer, v_a502, 5, '12:00', '14:00');
  end if;

  -- Software Engineering — placed in the Mon/Tue/Thu afternoon gaps left
  -- open by the other 5 courses (all free from 13:00 on those days),
  -- rather than a 6th day, to stay clash-free for a student in all 6.
  if not exists (select 1 from public.class_schedule where course_id = v_se and session_type = 'lecture') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_se, 'lecture', v_lecturer, v_a601, 1, '14:00', '16:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_se and session_type = 'tutorial') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_se, 'tutorial', v_lecturer, v_b305, 2, '14:00', '15:00');
  end if;
  if not exists (select 1 from public.class_schedule where course_id = v_se and session_type = 'practical') then
    insert into public.class_schedule (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time)
    values (v_se, 'practical', v_lecturer, v_c102, 4, '14:00', '16:00');
  end if;

  -- Align effective_from to the Monday of its week — the column defaults
  -- to current_date, which may itself be mid-week. "Week 1" in the
  -- student-facing timetable needs to start on a Monday so the 12-week
  -- term lines up cleanly with the Mon-Sun calendar-week view instead of
  -- starting on a partial week.
  update public.class_schedule
  set effective_from = date_trunc('week', effective_from)::date
  where effective_from <> date_trunc('week', effective_from)::date;

  -- Example replacement class: this week's Mobile App Dev tutorial (Wed
  -- 11:00-12:00) moves to Thursday 1:00-2:00 PM in the same room — matches
  -- the approved mockup and exercises the 'move' exception end-to-end.
  if v_mad_tutorial_schedule is not null and not exists (
    select 1 from public.class_schedule_exceptions
    where schedule_id = v_mad_tutorial_schedule
      and original_date = date_trunc('week', current_date)::date + 2
  ) then
    insert into public.class_schedule_exceptions
      (schedule_id, exception_type, original_date, course_id, session_type, lecturer_id, room_id,
       occurrence_date, start_time, end_time, created_by)
    values (
      v_mad_tutorial_schedule, 'move', date_trunc('week', current_date)::date + 2,
      v_mad, 'tutorial', v_lecturer, v_b305,
      date_trunc('week', current_date)::date + 3, '13:00', '14:00', v_lecturer
    );
  end if;
end $$;
