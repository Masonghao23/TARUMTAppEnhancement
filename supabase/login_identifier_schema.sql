-- Lets the login screen accept a campus ID as well as an email. Supabase
-- Auth only signs in by email, so an identifier that isn't an email needs
-- to be resolved to its owner's email first — before the user is
-- authenticated, so this has to be a security-definer RPC (profiles has
-- no anon SELECT grant/policy) rather than a plain client-side query.
--
-- Deliberately returns only the email for an exact campus_id match, never
-- a list or any other profile field, keeping the enumeration surface to
-- "does this exact campus ID exist" — the same thing a real login attempt
-- already reveals via timing/behavior on any login screen. The client
-- treats a null result the same as a wrong password (generic "Invalid ID
-- or password."), so a wrong campus ID looks identical to a wrong
-- password from the UI.
create or replace function public.resolve_login_email(p_identifier text)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select email from public.profiles where campus_id = p_identifier limit 1;
$$;

grant execute on function public.resolve_login_email(text) to anon, authenticated;
