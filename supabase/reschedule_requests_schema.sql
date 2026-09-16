-- Reschedule approval workflow. A staff member's reschedule/cancel no
-- longer writes to class_schedule_exceptions directly — it becomes a
-- pending request instead, which an admin approves (applying the change
-- via the existing create_schedule_exception) or rejects (nothing
-- changes). Admin's own reschedules stay instant, unchanged — see
-- create_schedule_exception's existing admin bypass.
--
-- Run this in the Supabase SQL editor AFTER timetable_stage3c_schema.sql
-- and notification_schema.sql (uses notify_user()).

create table if not exists public.reschedule_requests (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references public.class_schedule (id) on delete cascade,
  original_date date not null,
  course_id uuid not null references public.courses (id),
  session_type text not null check (session_type in ('lecture', 'tutorial', 'practical')),
  exception_type text not null check (exception_type in ('move', 'cancel')),
  occurrence_date date,
  start_time time,
  end_time time,
  room_id uuid references public.facilities (id),
  reason text not null,
  requested_by uuid not null references public.profiles (id),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  reviewed_by uuid references public.profiles (id),
  reviewed_at timestamptz,
  review_comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reschedule_requests_requested_by_idx
  on public.reschedule_requests (requested_by, created_at desc);
create index if not exists reschedule_requests_status_idx
  on public.reschedule_requests (status, created_at desc);

-- Every write goes through the RPCs below (all security definer) — the
-- table itself only needs a select grant, gated by RLS.
grant select on public.reschedule_requests to authenticated;

alter table public.reschedule_requests enable row level security;

drop policy if exists "reschedule_requests_select_own_or_admin" on public.reschedule_requests;
create policy "reschedule_requests_select_own_or_admin" on public.reschedule_requests
  for select using (auth.uid() = requested_by or public.current_user_role() = 'admin');

-- Staff submits a reschedule/cancel request for one of their own recurring
-- slots — mirrors create_schedule_exception's own validation so a request
-- can never describe a change that would fail once approved.
create or replace function public.request_class_reschedule(
  p_schedule_id uuid,
  p_original_date date,
  p_exception_type text,
  p_occurrence_date date,
  p_start_time time,
  p_end_time time,
  p_room_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_schedule record;
  v_id uuid;
  v_requester_name text;
  v_admin record;
begin
  if public.current_user_role() not in ('staff', 'admin') then
    return jsonb_build_object('success', false, 'reason', 'Only staff can request a reschedule.');
  end if;
  if p_exception_type not in ('move', 'cancel') then
    return jsonb_build_object('success', false, 'reason', 'Invalid request type.');
  end if;
  if p_reason is null or trim(p_reason) = '' then
    return jsonb_build_object('success', false, 'reason', 'A reason is required.');
  end if;

  select * into v_schedule from public.class_schedule where id = p_schedule_id;
  if not found then
    return jsonb_build_object('success', false, 'reason', 'Timetable slot not found.');
  end if;
  if v_schedule.lecturer_id <> auth.uid() then
    return jsonb_build_object('success', false, 'reason', 'You can only request a reschedule for your own classes.');
  end if;
  if p_exception_type = 'move'
     and (p_occurrence_date is null or p_start_time is null or p_end_time is null or p_room_id is null) then
    return jsonb_build_object('success', false, 'reason', 'New date, time and room are required to move a class.');
  end if;

  insert into public.reschedule_requests
    (schedule_id, original_date, course_id, session_type, exception_type,
     occurrence_date, start_time, end_time, room_id, reason, requested_by)
  values
    (p_schedule_id, p_original_date, v_schedule.course_id, v_schedule.session_type, p_exception_type,
     p_occurrence_date, p_start_time, p_end_time, p_room_id, trim(p_reason), auth.uid())
  returning id into v_id;

  select name into v_requester_name from public.profiles where id = auth.uid();

  for v_admin in select id from public.profiles where role = 'admin' loop
    perform public.notify_user(
      v_admin.id,
      'New reschedule request',
      coalesce(v_requester_name, 'A lecturer') || ' wants to ' ||
        case p_exception_type when 'move' then 'move' else 'cancel' end ||
        ' a class — tap to review.',
      'reschedule',
      'reschedule_request:' || v_id
    );
  end loop;

  return jsonb_build_object('success', true, 'requestId', v_id);
end;
$$;

grant execute on function public.request_class_reschedule(uuid, date, text, date, time, time, uuid, text) to authenticated;

-- The requester changes their own still-pending request.
create or replace function public.update_reschedule_request(
  p_request_id uuid,
  p_exception_type text,
  p_occurrence_date date,
  p_start_time time,
  p_end_time time,
  p_room_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request record;
begin
  select * into v_request from public.reschedule_requests
  where id = p_request_id and requested_by = auth.uid();
  if not found then
    return jsonb_build_object('success', false, 'reason', 'Request not found.');
  end if;
  if v_request.status <> 'pending' then
    return jsonb_build_object('success', false, 'reason', 'Only a pending request can be changed.');
  end if;
  if p_exception_type not in ('move', 'cancel') then
    return jsonb_build_object('success', false, 'reason', 'Invalid request type.');
  end if;
  if p_reason is null or trim(p_reason) = '' then
    return jsonb_build_object('success', false, 'reason', 'A reason is required.');
  end if;
  if p_exception_type = 'move'
     and (p_occurrence_date is null or p_start_time is null or p_end_time is null or p_room_id is null) then
    return jsonb_build_object('success', false, 'reason', 'New date, time and room are required to move a class.');
  end if;

  update public.reschedule_requests
  set exception_type = p_exception_type,
      occurrence_date = p_occurrence_date,
      start_time = p_start_time,
      end_time = p_end_time,
      room_id = p_room_id,
      reason = trim(p_reason),
      updated_at = now()
  where id = p_request_id;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.update_reschedule_request(uuid, text, date, time, time, uuid, text) to authenticated;

-- The requester withdraws their own still-pending request — no admin
-- action needed, just quietly removes it from the queue.
create or replace function public.withdraw_reschedule_request(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  update public.reschedule_requests
  set status = 'withdrawn', updated_at = now()
  where id = p_request_id and requested_by = auth.uid() and status = 'pending';

  get diagnostics v_count = row_count;
  if v_count = 0 then
    return jsonb_build_object('success', false, 'reason', 'Request not found or already reviewed.');
  end if;
  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.withdraw_reschedule_request(uuid) to authenticated;

-- Admin decides. Approving reuses create_schedule_exception verbatim
-- (already admin-bypassed for the ownership check) so there's exactly one
-- place that knows how to actually write a move/cancel exception —
-- rejecting just records the outcome, the timetable is untouched.
create or replace function public.review_reschedule_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request record;
  v_apply_result jsonb;
begin
  if public.current_user_role() <> 'admin' then
    return jsonb_build_object('success', false, 'reason', 'Only admin can review requests.');
  end if;
  if p_decision not in ('approved', 'rejected') then
    return jsonb_build_object('success', false, 'reason', 'Invalid decision.');
  end if;

  select * into v_request from public.reschedule_requests where id = p_request_id;
  if not found then
    return jsonb_build_object('success', false, 'reason', 'Request not found.');
  end if;
  if v_request.status <> 'pending' then
    return jsonb_build_object('success', false, 'reason', 'This request has already been reviewed.');
  end if;

  if p_decision = 'approved' then
    v_apply_result := public.create_schedule_exception(
      v_request.exception_type,
      v_request.schedule_id,
      v_request.original_date,
      v_request.course_id,
      v_request.session_type,
      v_request.room_id,
      v_request.occurrence_date,
      v_request.start_time,
      v_request.end_time
    );
    if not (v_apply_result ->> 'success')::boolean then
      return jsonb_build_object(
        'success', false,
        'reason', 'Could not apply the change: ' || (v_apply_result ->> 'reason')
      );
    end if;
  end if;

  update public.reschedule_requests
  set status = p_decision,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_comment = p_comment,
      updated_at = now()
  where id = p_request_id;

  perform public.notify_user(
    v_request.requested_by,
    case p_decision when 'approved' then 'Reschedule approved' else 'Reschedule rejected' end,
    case p_decision
      when 'approved' then 'Your reschedule request has been approved and applied to the timetable.'
      else 'Your reschedule request was rejected.' ||
        case when p_comment is not null and trim(p_comment) <> '' then ' Note: ' || p_comment else '' end
    end,
    'reschedule',
    'reschedule_reviewed:' || p_request_id
  );

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.review_reschedule_request(uuid, text, text) to authenticated;
