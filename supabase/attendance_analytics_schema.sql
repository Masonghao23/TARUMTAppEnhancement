-- Attendance analytics for staff — powers the "Attendance charts" screen
-- (headline KPIs, per-course trend, pass/at-risk split + student detail).
--
-- Scope rule matches the rest of the app: a lecturer sees only the courses
-- they're assigned to teach (class_schedule.lecturer_id, plus any session
-- they've actually run), an admin sees every course.
--
-- Percentages are hour-weighted, reusing calculate_course_attendance_hours()
-- so these numbers agree with what a student sees on their own screen and
-- with the 80% threshold the notification triggers already use. The one
-- exception is the trend, where each point is a single session — within one
-- session every student shares the same duration, so hour-weighting is moot
-- and the point is simply attended/enrolled for that session.
--
-- Run in the Supabase SQL editor AFTER attendance_status_schema.sql.

-- Courses the caller is allowed to see analytics for.
create or replace function public.staff_visible_course_ids()
returns table (course_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select distinct c.id
  from public.courses c
  where public.current_user_role() = 'admin'
     or exists (
       select 1 from public.class_schedule cs
       where cs.course_id = c.id and cs.lecturer_id = auth.uid()
     )
     or exists (
       select 1 from public.class_sessions s
       where s.course_id = c.id and s.lecturer_id = auth.uid()
     );
$$;

grant execute on function public.staff_visible_course_ids() to authenticated;

-- Course comparison + the headline KPIs above it.
create or replace function public.get_staff_course_attendance()
returns table (
  course_id uuid,
  course_code text,
  course_name text,
  student_count integer,
  attended_hours numeric,
  total_hours numeric,
  attendance_percent numeric,
  at_risk_count integer
)
language sql
stable
security definer
set search_path = public
as $$
  with visible as (
    select course_id from public.staff_visible_course_ids()
  ),
  -- One row per enrolled student per visible course. The lateral call is
  -- still one invocation per enrollment, same as the existing
  -- check_attendance_below_80 trigger — fine at this project's scale, and
  -- the set-based shape keeps it to a single round trip.
  per_student as (
    select
      ce.course_id,
      ce.student_id,
      h.attended_hours,
      h.total_hours,
      case when h.total_hours > 0
           then (h.attended_hours / h.total_hours) * 100
           else null end as percent
    from public.course_enrollments ce
    join visible v on v.course_id = ce.course_id
    cross join lateral public.calculate_course_attendance_hours(
      ce.student_id, ce.course_id
    ) h
  )
  select
    c.id,
    c.course_code,
    c.course_name,
    count(ps.student_id)::integer,
    coalesce(sum(ps.attended_hours), 0),
    coalesce(sum(ps.total_hours), 0),
    case when coalesce(sum(ps.total_hours), 0) > 0
         then round((sum(ps.attended_hours) / sum(ps.total_hours)) * 100, 1)
         else null end,
    count(*) filter (where ps.percent is not null and ps.percent < 80)::integer
  from public.courses c
  join visible v on v.course_id = c.id
  left join per_student ps on ps.course_id = c.id
  group by c.id, c.course_code, c.course_name
  order by c.course_code;
$$;

grant execute on function public.get_staff_course_attendance() to authenticated;

-- Trend: one point per completed class for this course, oldest first.
--
-- Counted the same way calculate_course_attendance_hours counts a student,
-- so the trend and the pie agree:
--   * only ended sessions — a class still being scanned would plot a
--     misleadingly low point that then becomes the chart's end label;
--   * attended = present/late records from students still enrolled, so
--     someone who scanned and later left can't push a point past 100%;
--   * enrolled = students still enrolled, minus anyone on leave for that
--     session (the hours function drops leave from a student's total too).
-- A student can't be both present and on leave for one session (unique on
-- session_id + student_id), so attended can never exceed enrolled.
create or replace function public.get_course_attendance_trend(p_course_id uuid)
returns table (
  session_id uuid,
  session_date date,
  session_type text,
  enrolled_count integer,
  attended_count integer,
  attendance_percent numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with sessions as (
    select s.id, s.occurrence_date, s.start_time, s.session_type
    from public.class_sessions s
    where s.course_id = p_course_id
      and s.status = 'ended'
      and exists (
        select 1 from public.staff_visible_course_ids() v
        where v.course_id = p_course_id
      )
  ),
  enrolled as (
    select student_id
    from public.course_enrollments
    where course_id = p_course_id
  ),
  per_session as (
    select
      se.id,
      se.occurrence_date,
      se.start_time,
      se.session_type,
      (
        select count(*)
        from enrolled e
        where not exists (
          select 1 from public.attendance_records ar
          where ar.session_id = se.id
            and ar.student_id = e.student_id
            and ar.status = 'leave'
        )
      )::integer as enrolled_n,
      (
        select count(*)
        from enrolled e
        join public.attendance_records ar
          on ar.session_id = se.id and ar.student_id = e.student_id
        where ar.status in ('present', 'late')
      )::integer as attended_n
    from sessions se
  )
  select
    ps.id,
    coalesce(ps.occurrence_date, (ps.start_time at time zone 'Asia/Kuala_Lumpur')::date),
    ps.session_type,
    ps.enrolled_n,
    ps.attended_n,
    case when ps.enrolled_n > 0
         then round((ps.attended_n::numeric / ps.enrolled_n) * 100, 1)
         else null end
  from per_session ps
  order by 2, ps.start_time;
$$;

grant execute on function public.get_course_attendance_trend(uuid) to authenticated;

-- Every enrolled student in one course with their hour-weighted standing —
-- powers the pass/at-risk pie and the per-student detail list under it.
create or replace function public.get_course_student_attendance(p_course_id uuid)
returns table (
  student_id uuid,
  student_name text,
  attended_hours numeric,
  total_hours numeric,
  attendance_percent numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    coalesce(p.name, ''),
    h.attended_hours,
    h.total_hours,
    case when h.total_hours > 0
         then round((h.attended_hours / h.total_hours) * 100, 1)
         else null end
  from public.course_enrollments ce
  join public.profiles p on p.id = ce.student_id
  cross join lateral public.calculate_course_attendance_hours(
    ce.student_id, ce.course_id
  ) h
  where ce.course_id = p_course_id
    and exists (
      select 1 from public.staff_visible_course_ids() v
      where v.course_id = p_course_id
    )
  order by
    case when h.total_hours > 0
         then h.attended_hours / h.total_hours else null end
    asc nulls last,
    p.name;
$$;

grant execute on function public.get_course_student_attendance(uuid) to authenticated;

-- Superseded: the cohort-distribution bar chart and the standalone at-risk
-- list were replaced by the per-course pie + student detail list above.
drop function if exists public.get_student_attendance_distribution();
drop function if exists public.get_at_risk_students();
