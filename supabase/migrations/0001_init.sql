-- Clera CRM — initial schema
--
-- Data is owned by a FIRM (a practice), and many staff members share it.
-- A signed-in user is resolved to their firm on login; everyone in the same
-- firm reads and writes the same CRM state.
--
--   firms         — one practice
--   firm_members  — which users belong to a firm, and their role
--   firm_invites  — pending invitations by email
--   crm_state     — the whole CRM state for a firm, as one JSONB document
--
-- Apply with:  supabase db push   (or paste into the dashboard SQL editor)

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.firms (
  id         uuid primary key default gen_random_uuid(),
  name       text        not null default 'My practice',
  created_at timestamptz not null default now()
);

create table if not exists public.firm_members (
  firm_id    uuid not null references public.firms (id)   on delete cascade,
  user_id    uuid not null references auth.users (id)     on delete cascade,
  role       text not null default 'staff' check (role in ('owner','admin','staff')),
  created_at timestamptz not null default now(),
  primary key (firm_id, user_id)
);
create index if not exists firm_members_user_idx on public.firm_members (user_id);

create table if not exists public.firm_invites (
  id         uuid primary key default gen_random_uuid(),
  firm_id    uuid not null references public.firms (id) on delete cascade,
  email      text not null,
  role       text not null default 'staff' check (role in ('admin','staff')),
  invited_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);

-- The CRM state, now keyed by firm rather than by user.
create table if not exists public.crm_state (
  firm_id    uuid primary key references public.firms (id) on delete cascade,
  state      jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id)
);

comment on table public.crm_state is
  'The full CRM state (clients, deadlines, documents, tasks, leads, onboarding) for a firm, as one JSONB document shared by all its staff.';

-- ---------------------------------------------------------------------------
-- Membership helpers (SECURITY DEFINER so they can be used inside RLS policies
-- without the policy recursing back into firm_members).
-- ---------------------------------------------------------------------------
create or replace function public.is_firm_member(f uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.firm_members
    where firm_id = f and user_id = auth.uid()
  );
$$;

create or replace function public.is_firm_admin(f uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.firm_members
    where firm_id = f and user_id = auth.uid() and role in ('owner','admin')
  );
$$;

-- ---------------------------------------------------------------------------
-- Row-Level Security
-- ---------------------------------------------------------------------------
alter table public.firms         enable row level security;
alter table public.firm_members  enable row level security;
alter table public.firm_invites  enable row level security;
alter table public.crm_state     enable row level security;

drop policy if exists "firms: members read"   on public.firms;
drop policy if exists "firms: admins update"  on public.firms;
create policy "firms: members read"  on public.firms for select using (public.is_firm_member(id));
create policy "firms: admins update" on public.firms for update using (public.is_firm_admin(id));

drop policy if exists "members: read own firm"    on public.firm_members;
drop policy if exists "members: admins remove"    on public.firm_members;
create policy "members: read own firm" on public.firm_members for select using (public.is_firm_member(firm_id));
create policy "members: admins remove" on public.firm_members for delete using (public.is_firm_admin(firm_id));

drop policy if exists "invites: admins read" on public.firm_invites;
create policy "invites: admins read" on public.firm_invites for select using (public.is_firm_admin(firm_id));

drop policy if exists "state: members read"   on public.crm_state;
drop policy if exists "state: members insert" on public.crm_state;
drop policy if exists "state: members update" on public.crm_state;
create policy "state: members read"   on public.crm_state for select using (public.is_firm_member(firm_id));
create policy "state: members insert" on public.crm_state for insert with check (public.is_firm_member(firm_id));
create policy "state: members update" on public.crm_state for update using (public.is_firm_member(firm_id)) with check (public.is_firm_member(firm_id));

-- keep updated_at honest on every write
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
drop trigger if exists trg_crm_state_touch on public.crm_state;
create trigger trg_crm_state_touch
  before update on public.crm_state
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- RPCs the app calls (all run as the definer so they can safely create rows
-- and read auth.users, while still checking auth.uid() themselves).
-- ---------------------------------------------------------------------------

-- Resolve the caller to a firm: reuse an existing membership, accept a pending
-- invite matching their email, or create a brand-new firm they own.
create or replace function public.bootstrap_firm()
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  uid    uuid := auth.uid();
  uemail text;
  fid    uuid;
  inv    public.firm_invites;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select firm_id into fid from public.firm_members where user_id = uid limit 1;
  if fid is not null then return fid; end if;

  select email into uemail from auth.users where id = uid;

  select * into inv from public.firm_invites
    where accepted_at is null and lower(email) = lower(uemail)
    order by created_at desc limit 1;

  if inv.id is not null then
    insert into public.firm_members (firm_id, user_id, role)
      values (inv.firm_id, uid, inv.role)
      on conflict do nothing;
    update public.firm_invites set accepted_at = now() where id = inv.id;
    return inv.firm_id;
  end if;

  insert into public.firms (name) values ('My practice') returning id into fid;
  insert into public.firm_members (firm_id, user_id, role) values (fid, uid, 'owner');
  insert into public.crm_state (firm_id, state, updated_by) values (fid, '{}'::jsonb, uid)
    on conflict do nothing;
  return fid;
end;
$$;

-- Invite a colleague by email (owner/admin only). They join automatically the
-- first time they sign in with that email.
create or replace function public.invite_member(p_email text, p_role text default 'staff')
returns void
language plpgsql security definer set search_path = public
as $$
declare fid uuid;
begin
  select firm_id into fid from public.firm_members
    where user_id = auth.uid() and role in ('owner','admin') limit 1;
  if fid is null then raise exception 'only an owner or admin can invite'; end if;
  if p_role not in ('admin','staff') then p_role := 'staff'; end if;

  delete from public.firm_invites
    where firm_id = fid and lower(email) = lower(p_email) and accepted_at is null;
  insert into public.firm_invites (firm_id, email, role, invited_by)
    values (fid, lower(p_email), p_role, auth.uid());
end;
$$;

-- The caller's firm roster (staff who have joined).
create or replace function public.firm_roster()
returns table (user_id uuid, email text, role text, is_you boolean)
language sql security definer set search_path = public
as $$
  select m.user_id, u.email, m.role, (m.user_id = auth.uid())
  from public.firm_members m
  join auth.users u on u.id = m.user_id
  where m.firm_id = (select firm_id from public.firm_members where user_id = auth.uid() limit 1)
  order by m.created_at;
$$;

-- Invites that haven't been accepted yet.
create or replace function public.pending_invites()
returns table (email text, role text)
language sql security definer set search_path = public
as $$
  select email, role from public.firm_invites
  where accepted_at is null
    and firm_id = (select firm_id from public.firm_members where user_id = auth.uid() limit 1)
  order by created_at;
$$;

grant execute on function public.bootstrap_firm()                to authenticated;
grant execute on function public.invite_member(text, text)       to authenticated;
grant execute on function public.firm_roster()                   to authenticated;
grant execute on function public.pending_invites()               to authenticated;
