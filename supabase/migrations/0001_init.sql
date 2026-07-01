-- Clera CRM — initial schema
-- Backs the two things the front-end talks to Supabase for:
--   1. crm_state  — one JSONB blob per signed-in user (the whole app state)
--   2. waitlist   — public sign-ups from the marketing landing page
--
-- Apply with either:
--   supabase db push                      (Supabase CLI, links to your project)
--   or paste into the SQL editor in the Supabase dashboard.

-- ---------------------------------------------------------------------------
-- crm_state: the entire CRM state for a user, saved as one JSONB document.
-- The front-end upserts { user_id, state, updated_at } and selects state by
-- user_id (see loadState() / saveNow() in the app). One row per user.
-- ---------------------------------------------------------------------------
create table if not exists public.crm_state (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  state      jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

comment on table public.crm_state is
  'Per-user CRM application state (clients, deadlines, documents, tasks, leads, onboarding) as a single JSONB document.';

alter table public.crm_state enable row level security;

-- A user may only ever see or touch their own row. auth.uid() is the id of the
-- currently authenticated user; the anon key with no session has a null uid and
-- therefore matches nothing.
drop policy if exists "crm_state: read own"   on public.crm_state;
drop policy if exists "crm_state: insert own" on public.crm_state;
drop policy if exists "crm_state: update own" on public.crm_state;
drop policy if exists "crm_state: delete own" on public.crm_state;

create policy "crm_state: read own"
  on public.crm_state for select
  using (auth.uid() = user_id);

-- upsert = insert ... on conflict update, so both insert and update policies
-- are required for saveNow()'s .upsert() to succeed.
create policy "crm_state: insert own"
  on public.crm_state for insert
  with check (auth.uid() = user_id);

create policy "crm_state: update own"
  on public.crm_state for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "crm_state: delete own"
  on public.crm_state for delete
  using (auth.uid() = user_id);

-- Keep updated_at honest even if a client forgets to send it.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_crm_state_touch on public.crm_state;
create trigger trg_crm_state_touch
  before update on public.crm_state
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- waitlist: sign-ups from the public landing page (index.html).
-- The page POSTs { email, firm_name, segment } with the anon key, so we allow
-- anonymous INSERT but no SELECT — nobody can read the list with the anon key,
-- only the service role (dashboard / server) can.
-- ---------------------------------------------------------------------------
create table if not exists public.waitlist (
  id         uuid primary key default gen_random_uuid(),
  email      text not null,
  firm_name  text,
  segment    text,
  created_at timestamptz not null default now()
);

comment on table public.waitlist is
  'Early-access sign-ups captured by the marketing landing page.';

-- Treat a repeat sign-up as the same person. The landing page already treats a
-- 409 (unique violation) as success, so a duplicate email is handled cleanly.
create unique index if not exists waitlist_email_unique
  on public.waitlist (lower(email));

alter table public.waitlist enable row level security;

drop policy if exists "waitlist: public insert" on public.waitlist;

-- Anyone (anon or authenticated) may add themselves; no read policy exists, so
-- the list is not exposed through the anon/authenticated API surface.
create policy "waitlist: public insert"
  on public.waitlist for insert
  to anon, authenticated
  with check (true);
