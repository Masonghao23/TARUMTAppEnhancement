-- Stage 1 of the Timetable feature: the recurring weekly schedule, one-off
-- exceptions (moved/cancelled/added classes), and a read-only weekly view
-- for students. Session-linking (class_sessions.schedule_id) and staff
-- write screens are later stages — this file only adds the schedule data
-- and a way to read it; nothing here changes how attendance is checked in
-- or calculated yet.
--
-- Run this in the Supabase SQL editor AFTER schema.sql and
-- attendance_schema.sql.
--
-- day_of_week uses ISO convention: 1 = Monday .. 7 = Sunday.

create table if not exists public.class_schedule (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses (id) on delete cascade,
  session_type text not null check (session_type in ('lecture', 'tutorial', 'practical')),
  lecturer_id uuid not null references public.profiles (id),
  room_id uuid not null references public.facilities (id),
  day_of_week smallint not null check (day_of_week between 1 and 7),
  start_time time not null,
  end_time time not null,
  -- The term this slot is active for — occurrences before effective_from or
  -- from term_weeks onward simply don't exist, rather than needing a
  -- separate "is this slot still active" flag.
  effective_from date not null default current_date,
  term_weeks integer not null default 12,
  created_at timestamptz not null default now(),
  constraint class_schedule_time_order check (end_time > start_time)
);

create index if not exists class_schedule_course_idx on public.class_schedule (course_id);
create index if not exists class_schedule_lecturer_idx on public.class_schedule (lecturer_id);

-- One-off overrides on top of the recurring pattern above:
--   'move'   — schedule_id + original_date identify the regular occurrence
--              being relocated; occurrence_date/start_time/end_time/room_id
--              are where it's moving to (the "replacement class").
--   'cancel' — schedule_id + original_date identify the occurrence being
--              skipped; occurrence_date = original_date, no new time/room.
--   'add'    — a standalone one-off session with no recurring parent at
--              all (schedule_id/original_date are null); course_id/
--              session_type/lecturer_id/room_id/occurrence_date/start_time/
--              end_time are all populated directly on this row instead.
create table if not exists public.class_schedule_exceptions (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid references public.class_schedule (id) on delete cascade,
  exception_type text not null check (exception_type in ('move', 'cancel', 'add')),
  original_date date,
  course_id uuid references public.courses (id),
  session_type text check (session_type in ('lecture', 'tutorial', 'practical')),
  lecturer_id uuid references public.profiles (id),
  room_id uuid references public.facilities (id),
  occurrence_date date not null,
  start_time time,
  end_time time,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  constraint class_schedule_exceptions_move_needs_parent
    check (exception_type = 'add' or (schedule_id is not null and original_date is not null)),
  constraint class_schedule_exceptions_add_needs_details
    check (exception_type <> 'add' or (course_id is not null and session_type is not null
      and lecturer_id is not null and room_id is not null)),
  constraint class_schedule_exceptions_move_needs_time
    check (exception_type <> 'move' or (start_time is not null and end_time is not null and room_id is not null))
);

create index if not exists class_schedule_exceptions_schedule_idx
  on public.class_schedule_exceptions (schedule_id, original_date);
create index if not exists class_schedule_exceptions_occurrence_idx
  on public.class_schedule_exceptions (occurrence_date);

-- Everyone can read the timetable/exceptions (same open-read pattern as
-- courses/facilities) — writes are staff/admin only, enforced both by RLS
-- here and re-checked server-side in the write RPCs added in a later stage.
grant select on public.class_schedule to authenticated;
grant select on public.class_schedule_exceptions to authenticated;
grant insert, update, delete on public.class_schedule to authenticated;
grant insert, update, delete on public.class_schedule_exceptions to authenticated;

alter table public.class_schedule enable row level security;
alter table public.class_schedule_exceptions enable row level security;

drop policy if exists "class_schedule_select_all" on public.class_schedule;
create policy "class_schedule_select_all" on public.class_schedule
  for select using (true);

drop policy if exists "class_schedule_write_staff" on public.class_schedule;
create policy "class_schedule_write_staff" on public.class_schedule
  for all using (public.current_user_role() in ('staff', 'admin'))
  with check (public.current_user_role() in ('staff', 'admin'));

drop policy if exists "class_schedule_exceptions_select_all" on public.class_schedule_exceptions;
create policy "class_schedule_exceptions_select_all" on public.class_schedule_exceptions
  for select using (true);

drop policy if exists "class_schedule_exceptions_write_staff" on public.class_schedule_exceptions;
create policy "class_schedule_exceptions_write_staff" on public.class_schedule_exceptions
  for all using (public.current_user_role() in ('staff', 'admin'))
  with check (public.current_user_role() in ('staff', 'admin'));

-- A student's timetable for one Mon-Sun week, with exceptions already
-- applied — the client never has to reconstruct the recurrence/override
-- logic itself. p_week_start must be a Monday.
--
-- status meanings:
--   normal     — regular recurring occurrence, unaffected by any exception
--   cancelled  — regular occurrence skipped this week (no replacement)
--   moved_away — regular occurrence relocated; moved_to_date/
--                moved_to_start_time say where, so the UI can show it
--                struck through in place with a "moved to ..." tag
--   moved_in   — the destination side of a 'move' exception, landing in
--                this particular week
--   added      — a standalone one-off session with no recurring parent
create or replace function public.get_my_timetable_week(
  p_student_id uuid,
  p_week_start date
)
returns table (
  occurrence_date date,
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
    r.room_id, f.room_name,
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
  left join ov_cancel oc on oc.schedule_id = r.schedule_id and oc.original_date = r.occ_date
  left join ov_move om on om.schedule_id = r.schedule_id and om.original_date = r.occ_date

  union all

  select
    l.occurrence_date, c.id, c.course_code, c.course_name, l.session_type, l.start_time, l.end_time,
    l.room_id, f.room_name,
    case when l.exception_type = 'add' then 'added' else 'moved_in' end as status,
    null::date, null::time
  from landing l
  join public.courses c on c.id = l.course_id
  join public.facilities f on f.id = l.room_id

  order by 1, 6;
$$;

grant execute on function public.get_my_timetable_week(uuid, date) to authenticated;
