-- Notification Module — Stage 3: the five time-based triggers from the
-- report's FRs (FR01, FR02, FR03, FR04, FR06 — FR05 is the preferences
-- toggle, already built in Stage 1). Each runs on a pg_cron schedule and
-- funnels through one shared dispatcher (notify_user) that checks the
-- relevant preference toggle, records the notification, and fires the
-- actual push via the send-push-notification Edge Function.
--
-- Run this in the Supabase SQL editor AFTER notification_schema.sql.

-- Dedup support -----------------------------------------------------------
-- A cron job runs every few minutes and re-scans the same window each
-- time, so every trigger needs a way to say "I already notified this
-- person about this specific thing" — dedupe_key is that marker. NULL for
-- broadcasts/manual sends (which don't need dedup), a deterministic string
-- per (trigger, subject, occurrence) for everything cron-driven.
alter table public.notifications
  add column if not exists dedupe_key text;

create unique index if not exists notifications_user_dedupe_idx
  on public.notifications (user_id, dedupe_key)
  where dedupe_key is not null;

create or replace function public.create_notification(
  p_user_id uuid,
  p_title text,
  p_message text,
  p_type text,
  p_dedupe_key text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.notifications (user_id, title, message, type, dedupe_key)
  values (p_user_id, p_title, p_message, p_type, p_dedupe_key)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.create_notification(uuid, text, text, text, text) to authenticated;

-- Service role key, for calling our own Edge Function from a cron job —
-- same Vault pattern as the Firebase key, same service_role-only grant as
-- get_firebase_service_account. Populated separately (see the app's
-- deployment notes) since the key itself isn't in this file.
create or replace function public.get_project_service_role_key()
returns text
language sql
security definer
set search_path = public, vault
as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = 'project_service_role_key'
  limit 1;
$$;

revoke all on function public.get_project_service_role_key() from public, anon, authenticated;
grant execute on function public.get_project_service_role_key() to service_role;

-- Dispatcher ----------------------------------------------------------------
-- Every trigger below calls this instead of writing to notifications or
-- calling the Edge Function directly — gating on the preference toggle,
-- recording the row, and firing delivery all happen in exactly one place.
create or replace function public.notify_user(
  p_user_id uuid,
  p_title text,
  p_message text,
  p_type text,
  p_dedupe_key text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_allowed boolean;
  v_notification_id uuid;
  v_service_key text;
begin
  select case p_type
    when 'attendance' then allow_attendance_alerts
    when 'parking' then allow_parking_alerts
    when 'class' then allow_class_reminders
    when 'booking' then allow_booking_reminders
    when 'reschedule' then allow_reschedule_updates
    else true
  end into v_allowed
  from public.notification_preferences
  where user_id = p_user_id;

  -- No row yet (never opened the preferences screen) means every toggle
  -- still defaults to true — same opt-out framing as the column defaults.
  if v_allowed is null then
    v_allowed := true;
  end if;
  if not v_allowed then
    return;
  end if;

  v_notification_id := public.create_notification(p_user_id, p_title, p_message, p_type, p_dedupe_key);
  -- Already sent (dedupe conflict) — nothing new to push.
  if v_notification_id is null then
    return;
  end if;

  v_service_key := public.get_project_service_role_key();
  if v_service_key is null then
    return;
  end if;

  perform net.http_post(
    url := 'https://yghfiautfaoteupmfsat.supabase.co/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object('userId', p_user_id, 'title', p_title, 'body', p_message)
  );
end;
$$;

-- FR01: attendance not recorded, class about to end -------------------------
-- A live session within 10 minutes of its scheduled end, for every
-- enrolled student who still has no attendance_records row for it.
create or replace function public.check_attendance_not_recorded() returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_now_myt timestamp := (now() at time zone 'Asia/Kuala_Lumpur');
begin
  for r in
    select s.id as session_id, c.course_name, ce.student_id
    from public.class_sessions s
    join public.courses c on c.id = s.course_id
    join public.course_enrollments ce on ce.course_id = s.course_id
    left join public.class_schedule cs on cs.id = s.schedule_id
    left join public.class_schedule_exceptions ex on ex.id = s.exception_id
    where s.status = 'active'
      and coalesce(cs.end_time, ex.end_time) is not null
      and coalesce(cs.end_time, ex.end_time)
            between v_now_myt::time and (v_now_myt + interval '10 minutes')::time
      and not exists (
        select 1 from public.attendance_records ar
        where ar.session_id = s.id and ar.student_id = ce.student_id
      )
  loop
    perform public.notify_user(
      r.student_id,
      'Attendance not recorded',
      r.course_name || ' ends soon — you haven''t checked in yet.',
      'attendance',
      'attendance_not_recorded:' || r.session_id
    );
  end loop;
end;
$$;

-- FR03: attendance below 80% -------------------------------------------------
-- Recomputed per enrolled student/course; dedupe_key includes today's date
-- so this fires at most once per day per course, not on every cron tick
-- while a student stays below the threshold.
create or replace function public.check_attendance_below_80() returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_hours record;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  for r in
    select ce.student_id, ce.course_id, c.course_name
    from public.course_enrollments ce
    join public.courses c on c.id = ce.course_id
  loop
    select * into v_hours
    from public.calculate_course_attendance_hours(r.student_id, r.course_id);

    if v_hours.total_hours > 0 and (v_hours.attended_hours / v_hours.total_hours) < 0.8 then
      perform public.notify_user(
        r.student_id,
        'Attendance below 80%',
        'Your attendance for ' || r.course_name || ' has dropped to ' ||
          round((v_hours.attended_hours / v_hours.total_hours) * 100) || '%.',
        'attendance',
        'attendance_below_80:' || r.course_id || ':' || v_today
      );
    end if;
  end loop;
end;
$$;

-- FR06: class reminder -------------------------------------------------------
-- Any occurrence (regular, or landing there via move/add) starting in the
-- next 15 minutes today, for every enrolled student — cancelled/moved-away
-- occurrences are excluded the same way get_lecturer_schedule_for_date
-- excludes them.
create or replace function public.check_class_reminders() returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_now_time time := (now() at time zone 'Asia/Kuala_Lumpur')::time;
begin
  for r in
    with today_occ as (
      select cs.id as schedule_id, cs.course_id, cs.start_time, cs.room_id
      from public.class_schedule cs
      where extract(isodow from v_today) = cs.day_of_week
        and v_today >= cs.effective_from
        and v_today < cs.effective_from + cs.term_weeks * 7
        and not exists (
          select 1 from public.class_schedule_exceptions ex
          where ex.schedule_id = cs.id and ex.original_date = v_today
            and ex.exception_type in ('cancel', 'move')
        )
      union all
      select null::uuid, ex.course_id, ex.start_time, ex.room_id
      from public.class_schedule_exceptions ex
      where ex.exception_type in ('move', 'add') and ex.occurrence_date = v_today
    )
    select o.course_id, o.start_time, c.course_name, f.room_name, ce.student_id
    from today_occ o
    join public.courses c on c.id = o.course_id
    join public.facilities f on f.id = o.room_id
    join public.course_enrollments ce on ce.course_id = o.course_id
    where o.start_time between v_now_time and (v_now_time + interval '15 minutes')
  loop
    perform public.notify_user(
      r.student_id,
      'Class reminder',
      r.course_name || ' starts soon at ' || r.room_name || '.',
      'class',
      'class_reminder:' || r.course_id || ':' || v_today || ':' || r.start_time
    );
  end loop;
end;
$$;

-- FR02: parking session ending soon ------------------------------------------
create or replace function public.check_parking_ending_soon() returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select pr.id, pr.user_id, ps.slot_number
    from public.parking_reservations pr
    join public.parking_slots ps on ps.id = pr.slot_id
    where pr.status = 'reserved'
      and pr.end_time between now() and now() + interval '15 minutes'
  loop
    perform public.notify_user(
      r.user_id,
      'Parking session ending soon',
      'Your reservation at slot ' || r.slot_number || ' ends in 15 minutes.',
      'parking',
      'parking_ending:' || r.id
    );
  end loop;
end;
$$;

-- FR04: parking duration exceeded --------------------------------------------
-- dedupe_key includes today's date so an abandoned overdue reservation
-- alerts once per day rather than going silent forever after the first.
create or replace function public.check_parking_duration_exceeded() returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select pr.id, pr.user_id, ps.slot_number
    from public.parking_reservations pr
    join public.parking_slots ps on ps.id = pr.slot_id
    where pr.status = 'reserved'
      and now() > pr.end_time
  loop
    perform public.notify_user(
      r.user_id,
      'Parking duration exceeded',
      'You have exceeded your reserved time at slot ' || r.slot_number || '.',
      'parking',
      'parking_exceeded:' || r.id || ':' || now()::date
    );
  end loop;
end;
$$;

-- Schedules -------------------------------------------------------------
-- Class reminders/attendance-not-recorded/parking are time-sensitive
-- (15/10/15-minute windows), so they run every 5 minutes. Attendance-below
-- -80% only changes meaningfully once classes end for the day and is more
-- expensive (recomputes hours for every enrollment), so it runs hourly.
select cron.unschedule(jobid) from cron.job where jobname = 'check_attendance_not_recorded';
select cron.schedule('check_attendance_not_recorded', '*/5 * * * *', $$select public.check_attendance_not_recorded()$$);

select cron.unschedule(jobid) from cron.job where jobname = 'check_class_reminders';
select cron.schedule('check_class_reminders', '*/5 * * * *', $$select public.check_class_reminders()$$);

select cron.unschedule(jobid) from cron.job where jobname = 'check_parking_ending_soon';
select cron.schedule('check_parking_ending_soon', '*/5 * * * *', $$select public.check_parking_ending_soon()$$);

select cron.unschedule(jobid) from cron.job where jobname = 'check_parking_duration_exceeded';
select cron.schedule('check_parking_duration_exceeded', '*/5 * * * *', $$select public.check_parking_duration_exceeded()$$);

select cron.unschedule(jobid) from cron.job where jobname = 'check_attendance_below_80';
select cron.schedule('check_attendance_below_80', '0 * * * *', $$select public.check_attendance_below_80()$$);
