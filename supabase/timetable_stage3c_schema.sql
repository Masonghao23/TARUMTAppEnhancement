-- Fixes two Manage Timetable gaps found after Stage 3 shipped:
--   1. Once a class was rescheduled, its original-day row (status
--      'moved_away') showed no "Moved to..." tag and no way to
--      edit/reschedule/undo it — every action was gated on status =
--      'normal', which excludes exactly the occurrences a staff member is
--      most likely to want to revisit.
--   2. create_schedule_exception rejected a second move/cancel for the
--      same occurrence outright ("already been rescheduled") instead of
--      letting staff change their mind.
--
-- Run this in the Supabase SQL editor AFTER timetable_stage3_schema.sql
-- and timetable_stage3b_schema.sql.

-- get_lecturer_occurrences: now returns the real exception id for
-- cancelled/moved_away rows (previously always null on those, since the
-- underlying regular-slot row never carried one), plus the full
-- destination of a move (end time + room), so the client can offer
-- Edit/Reschedule/Undo on them and show exactly where a class moved to.
-- New output columns mean the old signature has to be dropped first —
-- CREATE OR REPLACE can't change a function's OUT-parameter row type.
drop function if exists public.get_lecturer_occurrences(uuid, uuid[], date, date);

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
  moved_to_start_time time,
  moved_to_end_time time,
  moved_to_room_id uuid,
  moved_to_room_name text
)
language sql
stable
security definer
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
    r.session_type, r.start_time, r.end_time, r.room_id, f.room_name,
    case
      when oc.id is not null then 'cancelled'
      when om.id is not null then 'moved_away'
      else 'normal'
    end as status,
    om.occurrence_date, om.start_time, om.end_time, om.room_id, mf.room_name
  from regular r
  join public.courses c on c.id = r.course_id
  join public.facilities f on f.id = r.room_id
  left join ov_cancel oc on oc.schedule_id = r.schedule_id and oc.original_date = r.occ_date
  left join ov_move om on om.schedule_id = r.schedule_id and om.original_date = r.occ_date
  left join public.facilities mf on mf.id = om.room_id

  union all

  select
    l.occ_date, null::uuid, l.exception_id, c.id, c.course_code, c.course_name,
    l.session_type, l.start_time, l.end_time, l.room_id, f.room_name,
    case when l.exception_type = 'add' then 'added' else 'moved_in' end as status,
    null::date, null::time, null::time, null::uuid, null::text
  from landing l
  join public.courses c on c.id = l.course_id
  join public.facilities f on f.id = l.room_id

  order by 1, 8;
$$;

grant execute on function public.get_lecturer_occurrences(uuid, uuid[], date, date) to authenticated;

-- create_schedule_exception: a second move/cancel for the same occurrence
-- now replaces the earlier one instead of being rejected — staff changing
-- their mind about where/whether a class moved is the normal case, not an
-- error. Only refuses if a class_sessions row already references the
-- exception being replaced (i.e. attendance may already be underway
-- against it), which the foreign key on class_sessions.exception_id
-- enforces regardless of what this function does.
create or replace function public.create_schedule_exception(
  p_exception_type text,
  p_schedule_id uuid,
  p_original_date date,
  p_course_id uuid,
  p_session_type text,
  p_room_id uuid,
  p_occurrence_date date,
  p_start_time time,
  p_end_time time
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_schedule record;
  v_course_id uuid;
  v_session_type text;
  v_lecturer_id uuid;
  v_id uuid;
begin
  if public.current_user_role() not in ('staff', 'admin') then
    return jsonb_build_object('success', false, 'reason', 'Only staff can manage the timetable.');
  end if;

  if p_exception_type not in ('move', 'cancel', 'add') then
    return jsonb_build_object('success', false, 'reason', 'Invalid exception type.');
  end if;

  if p_exception_type in ('move', 'cancel') then
    if p_schedule_id is null or p_original_date is null then
      return jsonb_build_object('success', false, 'reason', 'Missing the slot/date being changed.');
    end if;

    select * into v_schedule from public.class_schedule where id = p_schedule_id;
    if not found then
      return jsonb_build_object('success', false, 'reason', 'Timetable slot not found.');
    end if;
    if v_schedule.lecturer_id <> auth.uid() and public.current_user_role() <> 'admin' then
      return jsonb_build_object('success', false, 'reason', 'You can only reschedule your own classes.');
    end if;

    if p_exception_type = 'move'
       and (p_occurrence_date is null or p_start_time is null or p_end_time is null or p_room_id is null) then
      return jsonb_build_object('success', false, 'reason', 'New date, time and room are required to move a class.');
    end if;

    -- A class started directly off the recurring slot (start_scheduled_session
    -- writes class_sessions.schedule_id + occurrence_date, exception_id null)
    -- has no exception row for the FK catch below to trip on — but moving or
    -- cancelling that occurrence now makes calculate_course_attendance_hours
    -- drop it from every enrolled student's totals, silently voiding scans
    -- already taken. Refuse retroactive changes to an occurrence that's
    -- already been held. (A reschedule requested while the class was still
    -- in the future has no session yet, so it's unaffected.)
    if exists (
      select 1 from public.class_sessions
      where schedule_id = p_schedule_id and occurrence_date = p_original_date
    ) then
      return jsonb_build_object(
        'success', false,
        'reason', 'This class has already been held — its schedule can no longer be changed.'
      );
    end if;

    begin
      delete from public.class_schedule_exceptions
      where schedule_id = p_schedule_id
        and original_date = p_original_date
        and exception_type in ('move', 'cancel');
    exception
      when foreign_key_violation then
        return jsonb_build_object(
          'success', false,
          'reason', 'Attendance has already been recorded against the current schedule for this class — it can no longer be changed.'
        );
    end;

    v_course_id := v_schedule.course_id;
    v_session_type := v_schedule.session_type;
    v_lecturer_id := v_schedule.lecturer_id;
  else
    if p_course_id is null or p_session_type is null or p_room_id is null
       or p_occurrence_date is null or p_start_time is null or p_end_time is null then
      return jsonb_build_object('success', false, 'reason', 'Course, type, room, date and time are all required.');
    end if;
    v_course_id := p_course_id;
    v_session_type := p_session_type;
    v_lecturer_id := auth.uid();
  end if;

  if p_exception_type = 'cancel' then
    insert into public.class_schedule_exceptions
      (schedule_id, exception_type, original_date, course_id, session_type, lecturer_id, room_id, occurrence_date, created_by)
    values
      (p_schedule_id, 'cancel', p_original_date, v_course_id, v_session_type, v_lecturer_id, v_schedule.room_id, p_original_date, auth.uid())
    returning id into v_id;
  elsif p_exception_type = 'move' then
    insert into public.class_schedule_exceptions
      (schedule_id, exception_type, original_date, course_id, session_type, lecturer_id, room_id,
       occurrence_date, start_time, end_time, created_by)
    values
      (p_schedule_id, 'move', p_original_date, v_course_id, v_session_type, v_lecturer_id, p_room_id,
       p_occurrence_date, p_start_time, p_end_time, auth.uid())
    returning id into v_id;
  else
    insert into public.class_schedule_exceptions
      (schedule_id, exception_type, original_date, course_id, session_type, lecturer_id, room_id,
       occurrence_date, start_time, end_time, created_by)
    values
      (null, 'add', null, v_course_id, v_session_type, v_lecturer_id, p_room_id,
       p_occurrence_date, p_start_time, p_end_time, auth.uid())
    returning id into v_id;
  end if;

  return jsonb_build_object('success', true, 'exceptionId', v_id);
end;
$$;

grant execute on function public.create_schedule_exception(text, uuid, date, uuid, text, uuid, date, time, time) to authenticated;

-- Reverts a move/cancel (back to the normal recurring occurrence) or
-- removes a standalone 'add' — the "Undo" action.
create or replace function public.remove_schedule_exception(
  p_exception_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lecturer_id uuid;
begin
  select lecturer_id into v_lecturer_id
  from public.class_schedule_exceptions
  where id = p_exception_id;

  if v_lecturer_id is null then
    return jsonb_build_object('success', false, 'reason', 'Not found.');
  end if;
  if v_lecturer_id <> auth.uid() and public.current_user_role() <> 'admin' then
    return jsonb_build_object('success', false, 'reason', 'You can only undo your own changes.');
  end if;

  begin
    delete from public.class_schedule_exceptions where id = p_exception_id;
  exception
    when foreign_key_violation then
      return jsonb_build_object(
        'success', false,
        'reason', 'Attendance has already been recorded against this — it can no longer be undone.'
      );
  end;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.remove_schedule_exception(uuid) to authenticated;
