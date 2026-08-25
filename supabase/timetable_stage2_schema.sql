-- Stage 2 of the Timetable feature: session-linking ("starting a session"
-- now means "starting a real timetable occurrence", never a freestanding
-- course+room pick) and the hour-based attendance calculation that depends
-- on it.
--
-- Run this in the Supabase SQL editor AFTER timetable_schema.sql and
-- timetable_seed.sql.

-- class_sessions additions ---------------------------------------------------
-- schedule_id/exception_id are nullable at the DB level (so pre-existing
-- rows created before this migration don't break), but every session the
-- app creates from now on goes through start_scheduled_session() below,
-- which always sets exactly one of them — there is no client code path
-- left that inserts a class_sessions row without one.
alter table public.class_sessions
  add column if not exists session_type text check (session_type in ('lecture', 'tutorial', 'practical')),
  add column if not exists schedule_id uuid references public.class_schedule (id),
  add column if not exists exception_id uuid references public.class_schedule_exceptions (id),
  add column if not exists occurrence_date date;

create index if not exists class_sessions_schedule_occurrence_idx
  on public.class_sessions (schedule_id, occurrence_date);
create index if not exists class_sessions_exception_idx
  on public.class_sessions (exception_id);

-- Re-issued (not just extended) so this file is self-contained — column
-- grants accumulate in Postgres, so re-running attendance_schema.sql's
-- original grant afterward would not remove these.
grant select (
  id, course_id, room_id, lecturer_id, qr_interval_seconds,
  status, start_time, end_time, session_type, schedule_id, exception_id, occurrence_date
) on public.class_sessions to authenticated;

-- A lecturer's own startable slots for one specific date — everything
-- get_my_timetable_week would mark 'moved_away'/'cancelled' for that date
-- is excluded outright, since those can't be started from here at all.
create or replace function public.get_lecturer_schedule_for_date(
  p_lecturer_id uuid,
  p_date date
)
returns table (
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
  session_id uuid,
  session_status text
)
language sql
stable
security definer
set search_path = public
as $$
  with regular as (
    select cs.id as schedule_id, null::uuid as exception_id,
           cs.course_id, cs.session_type, cs.start_time, cs.end_time, cs.room_id
    from public.class_schedule cs
    where cs.lecturer_id = p_lecturer_id
      and extract(isodow from p_date) = cs.day_of_week
      and p_date >= cs.effective_from
      and p_date < cs.effective_from + (cs.term_weeks * 7)
  ),
  ov_cancel as (
    select * from public.class_schedule_exceptions
    where exception_type = 'cancel' and original_date = p_date
  ),
  ov_move as (
    select * from public.class_schedule_exceptions
    where exception_type = 'move' and original_date = p_date
  ),
  landing as (
    select id as exception_id, null::uuid as schedule_id,
           course_id, session_type, start_time, end_time, room_id
    from public.class_schedule_exceptions
    where exception_type in ('move', 'add')
      and occurrence_date = p_date
      and lecturer_id = p_lecturer_id
  ),
  occurrences as (
    select r.schedule_id, r.exception_id, r.course_id, r.session_type, r.start_time, r.end_time, r.room_id
    from regular r
    left join ov_cancel oc on oc.schedule_id = r.schedule_id
    left join ov_move om on om.schedule_id = r.schedule_id
    where oc.id is null and om.id is null

    union all

    select l.schedule_id, l.exception_id, l.course_id, l.session_type, l.start_time, l.end_time, l.room_id
    from landing l
  )
  select
    o.schedule_id, o.exception_id, c.id, c.course_code, c.course_name,
    o.session_type, o.start_time, o.end_time, o.room_id, f.room_name,
    s.id as session_id, s.status as session_status
  from occurrences o
  join public.courses c on c.id = o.course_id
  join public.facilities f on f.id = o.room_id
  left join public.class_sessions s
    on (o.schedule_id is not null and s.schedule_id = o.schedule_id and s.occurrence_date = p_date)
    or (o.exception_id is not null and s.exception_id = o.exception_id)
  order by o.start_time;
$$;

grant execute on function public.get_lecturer_schedule_for_date(uuid, date) to authenticated;

-- "Starting a session" now means "starting a real timetable occurrence" —
-- schedule_id/exception_id come straight from what the lecturer tapped on
-- their timetable, not a freehand course/room pick. Idempotent: calling it
-- again for an occurrence that's already been started returns that same
-- session instead of erroring or creating a duplicate.
create or replace function public.start_scheduled_session(
  p_schedule_id uuid,
  p_exception_id uuid,
  p_occurrence_date date
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_course_id uuid;
  v_room_id uuid;
  v_lecturer_id uuid;
  v_session_type text;
  v_existing_id uuid;
  v_new_id uuid;
begin
  if (p_schedule_id is null) = (p_exception_id is null) then
    return jsonb_build_object('success', false, 'reason', 'Exactly one of schedule or exception must be given.');
  end if;

  if p_schedule_id is not null then
    select course_id, room_id, lecturer_id, session_type
      into v_course_id, v_room_id, v_lecturer_id, v_session_type
    from public.class_schedule where id = p_schedule_id;
  else
    select course_id, room_id, lecturer_id, session_type
      into v_course_id, v_room_id, v_lecturer_id, v_session_type
    from public.class_schedule_exceptions where id = p_exception_id;
  end if;

  if v_course_id is null then
    return jsonb_build_object('success', false, 'reason', 'Timetable slot not found.');
  end if;

  if auth.uid() <> v_lecturer_id and public.current_user_role() <> 'admin' then
    return jsonb_build_object('success', false, 'reason', 'Only the assigned lecturer can start this class.');
  end if;

  select id into v_existing_id from public.class_sessions
  where (p_schedule_id is not null and schedule_id = p_schedule_id and occurrence_date = p_occurrence_date)
     or (p_exception_id is not null and exception_id = p_exception_id);

  if v_existing_id is not null then
    -- Tapping the slot always means "this class is live right now" — if it
    -- was ended earlier (e.g. by mistake, or attendance needs reopening),
    -- resume it in place rather than leaving it stuck ended with no way
    -- back in. Same session, same QR seed, so already-recorded check-ins
    -- and the QR's timing are unaffected.
    update public.class_sessions
    set status = 'active', end_time = null
    where id = v_existing_id and status <> 'active';

    return jsonb_build_object('success', true, 'sessionId', v_existing_id, 'alreadyStarted', true);
  end if;

  insert into public.class_sessions
    (course_id, room_id, lecturer_id, session_type, schedule_id, exception_id, occurrence_date)
  values
    (v_course_id, v_room_id, v_lecturer_id, v_session_type, p_schedule_id, p_exception_id, p_occurrence_date)
  returning id into v_new_id;

  return jsonb_build_object('success', true, 'sessionId', v_new_id, 'alreadyStarted', false);
end;
$$;

grant execute on function public.start_scheduled_session(uuid, uuid, date) to authenticated;

-- Hour-based attendance for one student/course: sum of scheduled hours for
-- every occurrence that's already passed (Malaysia local time), vs the sum
-- of scheduled hours for the ones the student actually attended — replaces
-- calculate_attendance_percentage's session-count math. "Passed" checks
-- both date and time-of-day, not just date, so today's later classes don't
-- count until they've actually started.
create or replace function public.calculate_course_attendance_hours(
  p_student_id uuid,
  p_course_id uuid
) returns table (attended_hours numeric, total_hours numeric)
language sql
stable
security definer
set search_path = public
as $$
  with vars as (
    select (now() at time zone 'Asia/Kuala_Lumpur') as now_myt
  ),
  term as (
    select min(effective_from) as start_date,
           max(effective_from + term_weeks * 7 - 1) as end_date
    from public.class_schedule
  ),
  bound as (
    select t.start_date, least(t.end_date, v.now_myt::date) as end_date
    from term t, vars v
  ),
  regular as (
    select cs.id as schedule_id, null::uuid as exception_id, d::date as occ_date,
           cs.start_time, cs.end_time
    from public.class_schedule cs
    cross join bound b
    cross join lateral generate_series(
      greatest(cs.effective_from, b.start_date),
      least(cs.effective_from + cs.term_weeks * 7 - 1, b.end_date),
      interval '1 day'
    ) as d
    where cs.course_id = p_course_id
      and extract(isodow from d) = cs.day_of_week
  ),
  ov_cancel as (
    select * from public.class_schedule_exceptions where exception_type = 'cancel'
  ),
  ov_move as (
    select * from public.class_schedule_exceptions where exception_type = 'move'
  ),
  landing as (
    select cse.id as exception_id, null::uuid as schedule_id, cse.occurrence_date as occ_date,
           cse.start_time, cse.end_time
    from public.class_schedule_exceptions cse, bound b
    where cse.exception_type in ('move', 'add')
      and cse.course_id = p_course_id
      and cse.occurrence_date between b.start_date and b.end_date
  ),
  occurrences as (
    select r.schedule_id, r.exception_id, r.occ_date, r.start_time, r.end_time
    from regular r
    left join ov_cancel oc on oc.schedule_id = r.schedule_id and oc.original_date = r.occ_date
    left join ov_move om on om.schedule_id = r.schedule_id and om.original_date = r.occ_date
    where oc.id is null and om.id is null

    union all

    select l.schedule_id, l.exception_id, l.occ_date, l.start_time, l.end_time
    from landing l
  ),
  passed as (
    select o.*, extract(epoch from (o.end_time - o.start_time)) / 3600.0 as duration
    from occurrences o, vars v
    where o.occ_date < v.now_myt::date
       or (o.occ_date = v.now_myt::date and o.start_time <= v.now_myt::time)
  )
  select
    coalesce(sum(p.duration) filter (where exists (
      select 1
      from public.class_sessions s
      join public.attendance_records ar
        on ar.session_id = s.id and ar.student_id = p_student_id
      where (p.schedule_id is not null and s.schedule_id = p.schedule_id and s.occurrence_date = p.occ_date)
         or (p.exception_id is not null and s.exception_id = p.exception_id)
    )), 0) as attended_hours,
    coalesce(sum(p.duration), 0) as total_hours
  from passed p;
$$;

grant execute on function public.calculate_course_attendance_hours(uuid, uuid) to authenticated;
