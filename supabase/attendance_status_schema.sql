-- Attendance status expansion: adds 'absent' and 'leave' alongside the
-- existing 'present'/'late', and a lecturer-driven manual-override path
-- that works for a live session or any already-ended one.
--
-- "Auto-marked absent" is deliberately NOT a stored background job (no
-- pg_cron sweep) — a student with no attendance_records row for a session
-- that has ended is simply *treated* as absent wherever status is read
-- (the roster RPC below, and the hours calculation), which is simpler,
-- needs no scheduler, and works retroactively for sessions that already
-- ended before this migration ran. A real row only gets written once a
-- lecturer actually overrides someone's status (or a student scans).
--
-- Run this in the Supabase SQL editor AFTER attendance_schema.sql and
-- timetable_stage2_schema.sql.

alter table public.attendance_records
  drop constraint if exists attendance_records_status_check,
  add constraint attendance_records_status_check
    check (status in ('present', 'late', 'absent', 'leave')),
  alter column device_identifier drop not null,
  add column if not exists method text not null default 'scan' check (method in ('scan', 'manual')),
  add column if not exists marked_by uuid references public.profiles (id);

-- Every student enrolled in a session's course, with their effective
-- status for that specific session: a real attendance_records row if one
-- exists, otherwise 'absent' once the session has ended, or 'pending'
-- while it's still active (a still-ongoing class shouldn't show no-shows
-- as absent yet — the lecturer may still be about to display the QR).
create or replace function public.get_session_roster(p_session_id uuid)
returns table (
  student_id uuid,
  student_name text,
  status text,
  method text,
  recorded_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_session record;
begin
  select * into v_session from public.class_sessions where id = p_session_id;
  if not found then
    return;
  end if;

  if v_session.lecturer_id <> auth.uid() and public.current_user_role() <> 'admin' then
    return;
  end if;

  return query
    select
      p.id,
      coalesce(p.name, ''),
      coalesce(ar.status, case when v_session.status = 'ended' then 'absent' else 'pending' end),
      coalesce(ar.method, case when v_session.status = 'ended' then 'auto' else 'pending' end),
      ar.scan_timestamp
    from public.course_enrollments ce
    join public.profiles p on p.id = ce.student_id
    left join public.attendance_records ar
      on ar.session_id = p_session_id and ar.student_id = ce.student_id
    where ce.course_id = v_session.course_id
    order by p.name;
end;
$$;

grant execute on function public.get_session_roster(uuid) to authenticated;

-- Lecturer override — sets (or creates) one student's attendance status
-- for a session, live or already ended. Always stamped method='manual' so
-- the roster can tell a real scan apart from a lecturer's edit.
create or replace function public.set_attendance_status(
  p_session_id uuid,
  p_student_id uuid,
  p_status text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session record;
begin
  if p_status not in ('present', 'late', 'absent', 'leave') then
    return jsonb_build_object('success', false, 'reason', 'Invalid status.');
  end if;

  select * into v_session from public.class_sessions where id = p_session_id;
  if not found then
    return jsonb_build_object('success', false, 'reason', 'Session not found.');
  end if;

  if v_session.lecturer_id <> auth.uid() and public.current_user_role() <> 'admin' then
    return jsonb_build_object('success', false, 'reason', 'Only this class''s lecturer can edit attendance.');
  end if;

  if not exists (
    select 1 from public.course_enrollments
    where course_id = v_session.course_id and student_id = p_student_id
  ) then
    return jsonb_build_object('success', false, 'reason', 'Student is not enrolled in this course.');
  end if;

  insert into public.attendance_records (session_id, student_id, status, method, marked_by, device_identifier)
  values (p_session_id, p_student_id, p_status, 'manual', auth.uid(), null)
  on conflict (session_id, student_id) do update
    set status = excluded.status,
        method = 'manual',
        marked_by = auth.uid(),
        scan_timestamp = now();

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.set_attendance_status(uuid, uuid, text) to authenticated;

-- Re-issued with two changes now that attendance_records can hold
-- 'absent'/'leave' rows (previously every row meant "attended" by
-- construction, since only present/late were ever inserted):
--   1. The "attended" EXISTS check now explicitly requires present/late,
--      or a manually-marked absence would incorrectly count as attended.
--   2. An occurrence the student was on approved leave for is excluded
--      from total_hours entirely (not just left out of attended_hours) —
--      "leave should not harm their attendance percentage" means the
--      denominator shrinks too, same as if that class never happened for
--      them, rather than counting as a class they simply missed.
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
        and ar.status in ('present', 'late')
      where (p.schedule_id is not null and s.schedule_id = p.schedule_id and s.occurrence_date = p.occ_date)
         or (p.exception_id is not null and s.exception_id = p.exception_id)
    )), 0) as attended_hours,
    coalesce(sum(p.duration) filter (where not exists (
      select 1
      from public.class_sessions s
      join public.attendance_records ar
        on ar.session_id = s.id and ar.student_id = p_student_id
        and ar.status = 'leave'
      where (p.schedule_id is not null and s.schedule_id = p.schedule_id and s.occurrence_date = p.occ_date)
         or (p.exception_id is not null and s.exception_id = p.exception_id)
    )), 0) as total_hours
  from passed p;
$$;

grant execute on function public.calculate_course_attendance_hours(uuid, uuid) to authenticated;
