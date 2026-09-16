-- Notification Module — Stage 1: data model.
--
-- notifications/notification_preferences already existed in the DB from the
-- project's original scaffold (matching ERD Figure 4.9 exactly) but were
-- never wired up: no RLS, no useful grants (authenticated/anon somehow held
-- TRUNCATE on both, which bypasses RLS entirely and is revoked below), and
-- no functions. This file finishes wiring them up rather than recreating
-- them, and adds the one entity the ERD doesn't have at all: a place to
-- store each device's FCM token (see user_fcm_tokens below).
--
-- Run this in the Supabase SQL editor AFTER schema.sql. Note:
-- send_broadcast_announcement below calls notify_user(), which isn't
-- defined until notification_triggers.sql — harmless at CREATE time
-- (plpgsql doesn't validate a called function exists until it's actually
-- invoked), but a fresh database needs notification_triggers.sql applied
-- too before anyone actually sends a broadcast.

create extension if not exists pgcrypto;

-- notifications.type had no check constraint at all — added so a bad value
-- fails loudly instead of silently sitting in the table forever. 'reschedule'
-- added later, once new-request/approved/rejected notifications got their
-- own preference toggle instead of borrowing 'class'.
alter table public.notifications
  drop constraint if exists notifications_type_check,
  add constraint notifications_type_check
    check (type in ('attendance', 'parking', 'class', 'booking', 'broadcast', 'reschedule'));

create index if not exists notifications_user_id_sent_at_idx
  on public.notifications (user_id, sent_at desc);

-- UserFcmToken (extension beyond the ERD) -----------------------------------
-- The report's diagram describes *what* to send (Notification) and
-- *whether* to send it (NotificationPreference), but not *where* — a
-- user's Firebase Cloud Messaging token has to live somewhere the backend
-- can read it to call the FCM API. A user may have more than one device,
-- so the token itself (not the user) is part of the key.
create table if not exists public.user_fcm_tokens (
  user_id uuid not null references public.profiles (id) on delete cascade,
  token text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

-- Reschedule request updates (new request → admin, approved/rejected →
-- the requester) used to be filed under allow_class_reminders for lack of
-- a dedicated toggle — split out into its own column so turning off class
-- reminders doesn't also silently mute a staff member's own request
-- outcomes or an admin's incoming request queue.
alter table public.notification_preferences
  add column if not exists allow_reschedule_updates boolean not null default true;

-- Grants ----------------------------------------------------------------
-- Revoke the stray TRUNCATE grant found on both pre-existing tables — it
-- bypasses row-level security entirely, so any authenticated user could
-- otherwise wipe every user's notifications/preferences in one call. This
-- turns out to be a default-privilege setting on this Supabase project
-- (freshly created tables inherit it too — user_fcm_tokens got it on
-- creation above, despite never being granted it explicitly), so it has
-- to be revoked per table rather than being a one-off fix.
revoke truncate on public.notifications from authenticated, anon;
revoke truncate on public.notification_preferences from authenticated, anon;
revoke truncate on public.user_fcm_tokens from authenticated, anon;

grant select, update, delete on public.notifications to authenticated;
grant select, insert, update on public.notification_preferences to authenticated;
-- update is needed too, not just insert/delete — registerFcmToken() upserts
-- on (user_id, token) to bump updated_at on repeat calls, and PostgREST's
-- upsert compiles to INSERT ... ON CONFLICT DO UPDATE under the hood.
grant select, insert, update, delete on public.user_fcm_tokens to authenticated;

alter table public.notifications enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.user_fcm_tokens enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own" on public.notifications
  for select using (auth.uid() = user_id);

-- Only lets a user flip is_read on their own row — title/message/type/user_id
-- are never client-writable, only settable by the SECURITY DEFINER RPCs
-- below (create_notification, send_broadcast_announcement).
drop policy if exists "notifications_update_own_read_status" on public.notifications;
create policy "notifications_update_own_read_status" on public.notifications
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own" on public.notifications
  for delete using (auth.uid() = user_id);

drop policy if exists "notification_preferences_owner" on public.notification_preferences;
create policy "notification_preferences_owner" on public.notification_preferences
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "user_fcm_tokens_owner" on public.user_fcm_tokens;
create policy "user_fcm_tokens_owner" on public.user_fcm_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- RPCs ------------------------------------------------------------------

-- Every future trigger (attendance-below-80%, class reminder, parking
-- ending, etc.) funnels through this single insert path — keeps "who's
-- allowed to create a notification for someone else" answered in exactly
-- one place instead of duplicated per trigger.
create or replace function public.create_notification(
  p_user_id uuid,
  p_title text,
  p_message text,
  p_type text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.notifications (user_id, title, message, type)
  values (p_user_id, p_title, p_message, p_type)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.create_notification(uuid, text, text, text) to authenticated;

-- Upsert so the client never has to know whether a preferences row already
-- exists for this user (it won't, the first time they open the screen).
create or replace function public.upsert_notification_preferences(
  p_allow_attendance_alerts boolean,
  p_allow_parking_alerts boolean,
  p_allow_class_reminders boolean,
  p_allow_booking_reminders boolean,
  p_allow_reschedule_updates boolean default true
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notification_preferences
    (user_id, allow_attendance_alerts, allow_parking_alerts, allow_class_reminders, allow_booking_reminders, allow_reschedule_updates)
  values
    (auth.uid(), p_allow_attendance_alerts, p_allow_parking_alerts, p_allow_class_reminders, p_allow_booking_reminders, p_allow_reschedule_updates)
  on conflict (user_id) do update
    set allow_attendance_alerts = excluded.allow_attendance_alerts,
        allow_parking_alerts = excluded.allow_parking_alerts,
        allow_class_reminders = excluded.allow_class_reminders,
        allow_booking_reminders = excluded.allow_booking_reminders,
        allow_reschedule_updates = excluded.allow_reschedule_updates;
end;
$$;

-- create or replace can't change the parameter list of an existing
-- function without dropping the old signature first — p_allow_reschedule_
-- updates is new, so the 4-arg overload from before would otherwise stick
-- around alongside this 5-arg one and PostgREST wouldn't know which to use.
drop function if exists public.upsert_notification_preferences(boolean, boolean, boolean, boolean);

grant execute on function public.upsert_notification_preferences(boolean, boolean, boolean, boolean, boolean) to authenticated;

-- Broadcast Announcement (use case 4.2.4, Table 4.12) — staff-only, no
-- preference gate (per the report, there's no opt-out flow for it). Target
-- group is either every student, every staff/admin, or everyone.
-- Re-issued (originally a direct bulk insert, from before notify_user()
-- existed) to route through notify_user() per recipient instead — that's
-- the only thing that actually calls the Edge Function to push, so the
-- direct-insert version silently never sent a real push, only ever
-- writing the in-app row. notify_user()'s own case-statement already
-- treats 'broadcast' as always-allowed (no preference toggle gates it),
-- matching the "can't be turned off" framing on the preferences screen.
create or replace function public.send_broadcast_announcement(
  p_title text,
  p_message text,
  p_target text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
  v_recipient record;
begin
  if public.current_user_role() not in ('staff', 'admin') then
    return jsonb_build_object('success', false, 'reason', 'Only staff can send an announcement.');
  end if;

  if p_target not in ('students', 'staff', 'all') then
    return jsonb_build_object('success', false, 'reason', 'Invalid target group.');
  end if;

  if p_title is null or trim(p_title) = '' or p_message is null or trim(p_message) = '' then
    return jsonb_build_object('success', false, 'reason', 'Title and message are required.');
  end if;

  for v_recipient in
    select p.id from public.profiles p
    where case p_target
      when 'students' then p.role = 'student'
      when 'staff' then p.role in ('staff', 'admin')
      else true
    end
  loop
    perform public.notify_user(v_recipient.id, p_title, p_message, 'broadcast');
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('success', true, 'recipientCount', v_count);
end;
$$;

grant execute on function public.send_broadcast_announcement(text, text, text) to authenticated;

-- A device's FCM token is only ever meaningful for whoever is currently
-- signed in on it — but RLS on user_fcm_tokens (correctly) stops a client
-- from touching another user's row, so nothing ever released a token when
-- a different account signed in on the same device later. That let two
-- accounts end up sharing one token (e.g. testing as one student, then
-- another, on the same phone), so a broadcast to both silently pushed
-- twice to that one physical device. This RPC is the fix: security
-- definer, so it can atomically drop *any* other owner's claim on this
-- exact token before (re)claiming it for the caller — a token belongs to
-- at most one account at a time.
create or replace function public.claim_fcm_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.user_fcm_tokens
  where token = p_token and user_id <> auth.uid();

  insert into public.user_fcm_tokens (user_id, token, updated_at)
  values (auth.uid(), p_token, now())
  on conflict (user_id, token) do update set updated_at = now();
end;
$$;

grant execute on function public.claim_fcm_token(text) to authenticated;

-- Lets the send-push-notification Edge Function (running as service_role)
-- read the Firebase Admin SDK key out of Vault without needing the vault
-- schema exposed through PostgREST at all — service_role is the only
-- grantee, so no client app can ever reach this, even by guessing the
-- function name.
create or replace function public.get_firebase_service_account()
returns text
language sql
security definer
set search_path = public, vault
as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = 'firebase_service_account_json'
  limit 1;
$$;

revoke all on function public.get_firebase_service_account() from public, anon, authenticated;
grant execute on function public.get_firebase_service_account() to service_role;
