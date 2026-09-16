-- Project-wide fix: every table in public was created via the `postgres`
-- role (every schema.sql file this project has ever run, including the
-- original bootstrap, connects as postgres), and this project's default
-- ACL for postgres-owned tables only grants TRUNCATE/REFERENCES/TRIGGER to
-- anon/authenticated/service_role — never SELECT/INSERT/UPDATE/DELETE.
-- Every table has needed an explicit grant to authenticated to work at
-- all (which every schema.sql file in this project already does, which is
-- why this went unnoticed for authenticated) — but nothing ever explicitly
-- granted service_role anything, because until the Notification module's
-- Edge Function, nothing needed direct PostgREST table access as
-- service_role. This was silently breaking admin-create-user's
-- course_enrollments insert the entire time it's existed (it degrades to
-- a non-fatal warning rather than a hard error, so it never surfaced).
--
-- Two parts: fix every existing table right now, and fix the default so
-- every *future* table gets this automatically instead of needing to
-- remember it per schema file.

-- Part 1: every existing table, right now.
do $$
declare
  t record;
begin
  for t in
    select tablename from pg_tables where schemaname = 'public'
  loop
    execute format(
      'grant select, insert, update, delete on public.%I to service_role',
      t.tablename
    );
  end loop;
end $$;

-- Part 2: every table created from now on, automatically.
alter default privileges for role postgres in schema public
  grant select, insert, update, delete on tables to service_role;
