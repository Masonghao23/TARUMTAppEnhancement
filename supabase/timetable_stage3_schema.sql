-- Stage 3 of the Timetable feature: staff-facing write paths — creating
-- and editing recurring class_schedule slots, and creating exceptions
-- (move/cancel/add). Nothing before this stage could write to either
-- table outside of the seed script.
--
-- Run this in the Supabase SQL editor AFTER timetable_stage2_schema.sql.

-- Create or edit a recurring weekly slot. A new slot (p_id null) takes on
-- the term's existing effective_from/term_weeks so it lines up with every
-- other slot, rather than starting its own separate term. lecturer_id is
-- always the caller for a new slot — there is no "assign to someone else"
-- UI, so this doesn't try to support it server-side either.
create or replace function public.upsert_class_schedule(
  p_id uuid,
  p_course_id uuid,
  p_session_type text,
  p_room_id uuid,
  p_day_of_week smallint,
  p_start_time time,
  p_end_time time
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_effective_from date;
  v_term_weeks integer;
  v_existing_lecturer uuid;
  v_id uuid;
begin
  if public.current_user_role() not in ('staff', 'admin') then
    return jsonb_build_object('success', false, 'reason', 'Only staff can manage the timetable.');
  end if;

  if p_end_time <= p_start_time then
    return jsonb_build_object('success', false, 'reason', 'End time must be after start time.');
  end if;

  if p_id is not null then
    select lecturer_id into v_existing_lecturer from public.class_schedule where id = p_id;
    if v_existing_lecturer is null then
      return jsonb_build_object('success', false, 'reason', 'Slot not found.');
    end if;
    if v_existing_lecturer <> auth.uid() and public.current_user_role() <> 'admin' then
      return jsonb_build_object('success', false, 'reason', 'You can only edit your own slots.');
    end if;

    update public.class_schedule
    set course_id = p_course_id,
        session_type = p_session_type,
        room_id = p_room_id,
        day_of_week = p_day_of_week,
        start_time = p_start_time,
        end_time = p_end_time
    where id = p_id
    returning id into v_id;
  else
    select effective_from, term_weeks into v_effective_from, v_term_weeks
    from public.class_schedule
    limit 1;
    if v_effective_from is null then
      v_effective_from := date_trunc('week', current_date)::date;
      v_term_weeks := 12;
    end if;

    insert into public.class_schedule
      (course_id, session_type, lecturer_id, room_id, day_of_week, start_time, end_time, effective_from, term_weeks)
    values
      (p_course_id, p_session_type, auth.uid(), p_room_id, p_day_of_week, p_start_time, p_end_time, v_effective_from, v_term_weeks)
    returning id into v_id;
  end if;

  return jsonb_build_object('success', true, 'scheduleId', v_id);
exception
  when check_violation then
    return jsonb_build_object('success', false, 'reason', 'Invalid session type or day of week.');
end;
$$;

grant execute on function public.upsert_class_schedule(uuid, uuid, text, uuid, smallint, time, time) to authenticated;

-- Creates a 'move' (replacement class), 'cancel', or 'add' (standalone
-- extra class) exception. For move/cancel, course/session_type/lecturer
-- are taken from the schedule row being changed, not from the caller —
-- only 'add' needs them supplied directly, since it has no recurring
-- parent to inherit from.
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

    if exists (
      select 1 from public.class_schedule_exceptions
      where schedule_id = p_schedule_id
        and original_date = p_original_date
        and exception_type in ('move', 'cancel')
    ) then
      return jsonb_build_object('success', false, 'reason', 'This class has already been rescheduled or cancelled for that date.');
    end if;

    if p_exception_type = 'move'
       and (p_occurrence_date is null or p_start_time is null or p_end_time is null or p_room_id is null) then
      return jsonb_build_object('success', false, 'reason', 'New date, time and room are required to move a class.');
    end if;

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
