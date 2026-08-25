-- Manage-timetable calendar view: a lecturer's own occurrences across an
-- arbitrary date range (a calendar month, in practice), optionally
-- filtered to a set of courses — powers the course-picker -> calendar ->
-- day-detail management flow. Same recurrence/exception expansion as
-- get_my_timetable_week, generalized from "one Mon-Sun week for a
-- student's enrolled courses" to "any date range for a lecturer's own
-- courses", and additionally exposes schedule_id/exception_id so the
-- client can act on what it's showing (edit/reschedule).
create or replace function public.get_lecturer_occurrences(
  p_lecturer_id uuid,
  p_course_ids uuid[],
  p_from date,
  p_to date
)
returns table (
  occurrence_date date,
  schedule_id uuid,
  exception_id uuid,
  course_id uuid,
  course_code text,
  course_name text,
  session_type text,
  start_time time,
  end_time time,
  room_id uuid,
  room_name text,
  status text,
  moved_to_date date,
  moved_to_start_time time
)
language sql
stable
security definer
set search_path = public
as $$
  with regular as (
    select
      d::date as occ_date,
      cs.id as schedule_id, null::uuid as exception_id,
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
      id as exception_id, null::uuid as schedule_id,
      course_id, session_type, start_time, end_time, room_id, exception_type
    from public.class_schedule_exceptions
    where exception_type in ('move', 'add')
      and lecturer_id = p_lecturer_id
      and (p_course_ids is null or course_id = any(p_course_ids))
      and occurrence_date between p_from and p_to
  )
  select
    r.occ_date, r.schedule_id, r.exception_id, c.id, c.course_code, c.course_name,
    r.session_type, r.start_time, r.end_time, r.room_id, f.room_name,
    case
      when oc.id is not null then 'cancelled'
      when om.id is not null then 'moved_away'
      else 'normal'
    end as status,
    om.occurrence_date, om.start_time
  from regular r
  join public.courses c on c.id = r.course_id
  join public.facilities f on f.id = r.room_id
  left join ov_cancel oc on oc.schedule_id = r.schedule_id and oc.original_date = r.occ_date
  left join ov_move om on om.schedule_id = r.schedule_id and om.original_date = r.occ_date

  union all

  select
    l.occ_date, l.schedule_id, l.exception_id, c.id, c.course_code, c.course_name,
    l.session_type, l.start_time, l.end_time, l.room_id, f.room_name,
    case when l.exception_type = 'add' then 'added' else 'moved_in' end as status,
    null::date, null::time
  from landing l
  join public.courses c on c.id = l.course_id
  join public.facilities f on f.id = l.room_id

  order by 1, 8;
$$;

grant execute on function public.get_lecturer_occurrences(uuid, uuid[], date, date) to authenticated;
