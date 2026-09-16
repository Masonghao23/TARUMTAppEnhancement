-- Adds building_name alongside room_name in both timetable RPCs, so the
-- UI can show "where the class is" as a clear "Building · Room" location
-- line instead of just the room code. class_schedule.room_id was already
-- correctly populated for every row (verified directly) -- this was a
-- display clarity gap, not a missing-data one.
--
-- Run this in the Supabase SQL editor AFTER timetable_stage3c_schema.sql.
-- Both functions change their RETURNS TABLE shape, so they must be
-- dropped first -- CREATE OR REPLACE cannot alter a function's return type.

drop function if exists public.get_my_timetable_week(uuid, date);

create function public.get_my_timetable_week(p_student_id uuid, p_week_start date)
returns table (
  occurrence_date date, course_id uuid, course_code text, course_name text,
  session_type text, start_time time, end_time time,
  room_id uuid, room_name text, building_name text,
  status text, moved_to_date date, moved_to_start_time time
)
language sql
stable security definer
set search_path = public
as $$
  with enrolled as (
    select course_id from public.course_enrollments where student_id = p_student_id
  ),
  regular as (
    select
      (p_week_start + (cs.day_of_week - 1))::date as occ_date,
      cs.id as schedule_id,
      cs.course_id, cs.session_type, cs.start_time, cs.end_time, cs.room_id
    from public.class_schedule cs
    join enrolled e on e.course_id = cs.course_id
    where (p_week_start + (cs.day_of_week - 1))::date >= cs.effective_from
      and (p_week_start + (cs.day_of_week - 1))::date < cs.effective_from + (cs.term_weeks * 7)
  ),
  ov_cancel as (
    select * from public.class_schedule_exceptions
    where exception_type = 'cancel'
      and original_date >= p_week_start and original_date < p_week_start + 7
  ),
  ov_move as (
    select * from public.class_schedule_exceptions
    where exception_type = 'move'
      and original_date >= p_week_start and original_date < p_week_start + 7
  ),
  landing as (
    select cse.*
    from public.class_schedule_exceptions cse
    where cse.occurrence_date >= p_week_start and cse.occurrence_date < p_week_start + 7
      and cse.exception_type in ('move', 'add')
      and (
        cse.exception_type = 'add'
        or exists (select 1 from enrolled e where e.course_id = cse.course_id)
      )
  )
  select
    r.occ_date, c.id, c.course_code, c.course_name, r.session_type, r.start_time, r.end_time,
    r.room_id, f.room_name, b.building_name,
    case
      when oc.id is not null then 'cancelled'
      when om.id is not null then 'moved_away'
      else 'normal'
    end as status,
    om.occurrence_date as moved_to_date,
    om.start_time as moved_to_start_time
  from regular r
  join public.courses c on c.id = r.course_id
  join public.facilities f on f.id = r.room_id
  left join public.buildings b on b.id = f.building_id
  left join ov_cancel oc on oc.schedule_id = r.schedule_id and oc.original_date = r.occ_date
  left join ov_move om on om.schedule_id = r.schedule_id and om.original_date = r.occ_date

  union all

  select
    l.occurrence_date, c.id, c.course_code, c.course_name, l.session_type, l.start_time, l.end_time,
    l.room_id, f.room_name, b.building_name,
    case when l.exception_type = 'add' then 'added' else 'moved_in' end as status,
    null::date, null::time
  from landing l
  join public.courses c on c.id = l.course_id
  join public.facilities f on f.id = l.room_id
  left join public.buildings b on b.id = f.building_id

  order by 1, 6;
$$;

grant execute on function public.get_my_timetable_week(uuid, date) to authenticated;

drop function if exists public.get_lecturer_occurrences(uuid, uuid[], date, date);

create function public.get_lecturer_occurrences(p_lecturer_id uuid, p_course_ids uuid[], p_from date, p_to date)
returns table (
  occurrence_date date, schedule_id uuid, exception_id uuid, course_id uuid,
  course_code text, course_name text, session_type text, start_time time, end_time time,
  room_id uuid, room_name text, building_name text,
  status text, moved_to_date date, moved_to_start_time time, moved_to_end_time time,
  moved_to_room_id uuid, moved_to_room_name text, moved_to_building_name text
)
language sql
stable security definer
set search_path = public
as $$
  with regular as (
    select
      d::date as occ_date,
      cs.id as schedule_id,
      cs.course_id, cs.session_type, cs.start_time, cs.end_time, cs.room_id
    from public.class_schedule cs
    cross join lateral generate_series(
      greatest(cs.effective_from, p_from),
      least(cs.effective_from + cs.term_weeks * 7 - 1, p_to),
      interval '1 day'
    ) as d
    where cs.lecturer_id = p_lecturer_id
      and (p_course_ids is null or cs.course_id = any(p_course_ids))
      and extract(isodow from d) = cs.day_of_week
  ),
  ov_cancel as (
    select * from public.class_schedule_exceptions
    where exception_type = 'cancel'
      and original_date between p_from and p_to
  ),
  ov_move as (
    select * from public.class_schedule_exceptions
    where exception_type = 'move'
      and original_date between p_from and p_to
  ),
  landing as (
    select
      occurrence_date as occ_date,
      id as exception_id,
      course_id, session_type, start_time, end_time, room_id, exception_type
    from public.class_schedule_exceptions
    where exception_type in ('move', 'add')
      and lecturer_id = p_lecturer_id
      and (p_course_ids is null or course_id = any(p_course_ids))
      and occurrence_date between p_from and p_to
  )
  select
    r.occ_date, r.schedule_id,
    coalesce(oc.id, om.id) as exception_id,
    c.id, c.course_code, c.course_name,
    r.session_type, r.start_time, r.end_time, r.room_id, f.room_name, b.building_name,
    case
      when oc.id is not null then 'cancelled'
      when om.id is not null then 'moved_away'
      else 'normal'
    end as status,
    om.occurrence_date, om.start_time, om.end_time, om.room_id, mf.room_name, mb.building_name
  from regular r
  join public.courses c on c.id = r.course_id
  join public.facilities f on f.id = r.room_id
  left join public.buildings b on b.id = f.building_id
  left join ov_cancel oc on oc.schedule_id = r.schedule_id and oc.original_date = r.occ_date
  left join ov_move om on om.schedule_id = r.schedule_id and om.original_date = r.occ_date
  left join public.facilities mf on mf.id = om.room_id
  left join public.buildings mb on mb.id = mf.building_id

  union all

  select
    l.occ_date, null::uuid, l.exception_id, c.id, c.course_code, c.course_name,
    l.session_type, l.start_time, l.end_time, l.room_id, f.room_name, b.building_name,
    case when l.exception_type = 'add' then 'added' else 'moved_in' end as status,
    null::date, null::time, null::time, null::uuid, null::text, null::text
  from landing l
  join public.courses c on c.id = l.course_id
  join public.facilities f on f.id = l.room_id
  left join public.buildings b on b.id = f.building_id

  order by 1, 8;
$$;

grant execute on function public.get_lecturer_occurrences(uuid, uuid[], date, date) to authenticated;
