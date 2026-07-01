# Clera backend (Supabase)

The Clera CRM front-end (`index (2) - Copy (1).html`) is wired to **Supabase**.
This directory is the backend that satisfies that contract.

| What the app does | Backend piece |
|---|---|
| Sign in / create account | **Supabase Auth** (email/password) — enable it in the dashboard |
| Resolve which **firm** a user belongs to (create one, or join via invite) | `bootstrap_firm()` RPC — `migrations/0001_init.sql` |
| Save & load the whole CRM, shared by everyone in the firm | **`crm_state` table** (keyed by `firm_id`) + Row-Level Security |
| Invite colleagues / list the team | `invite_member()`, `firm_roster()`, `pending_invites()` RPCs |
| AI onboarding agent + AI chasing / drafting | **`ai-chase` Edge Function** — `functions/ai-chase/` |

## Multi-staff: how firm sharing works

Data belongs to a **firm**, not a user. The tables are:

- `firms` — one practice.
- `firm_members` — which users belong to a firm and their role (`owner` / `admin` / `staff`).
- `firm_invites` — pending invitations by email.
- `crm_state` — the whole CRM state for the firm, as one JSONB document.

On login the app calls `bootstrap_firm()`, which:
1. returns the firm you already belong to, or
2. accepts a pending invite that matches your email, or
3. creates a brand-new firm you own.

Everyone in the same firm reads and writes the same `crm_state` row, and the app
subscribes to Supabase Realtime so a colleague's changes appear live ("Updated by
a colleague"). Row-Level Security means a user can only ever touch their own
firm's data — which is what makes shipping the public anon key safe.

Owners/admins can invite staff from **Settings → Team**; the invitee joins
automatically the first time they create an account with that email.

## Setup

1. **CLI + link**
   ```bash
   npm install -g supabase && supabase login
   supabase link --project-ref vhkzpzebsnlworotwyfg
   ```
2. **Create tables, policies and RPCs**
   ```bash
   supabase db push        # or paste migrations/0001_init.sql in the SQL editor
   ```
3. **Enable email auth** — Dashboard → Authentication → Providers → Email. For a
   smooth demo, turn *off* "Confirm email" so new accounts sign in straight away.
4. **Enable Realtime (optional but recommended)** — Dashboard → Database →
   Replication → add `crm_state` to the `supabase_realtime` publication. Without
   it, saves still work; you just won't get live colleague sync.
5. **Deploy the AI function**
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   supabase functions deploy ai-chase
   ```
   Optionally pin a cheaper model: `supabase secrets set CLERA_AI_MODEL=claude-haiku-4-5`

## The AI onboarding agent

`ai-chase` is a small Edge Function that calls the Claude Messages API with the
API key kept server-side. The app uses it for:

- the **onboarding agent** (per-client onboarding plan + personalised welcome
  email), and
- the **document chasing** drafts.

`aiGenerate(prompt, fallback)` in the front-end calls it and falls back to a local
template if it's unreachable, so AI features degrade gracefully and never break
the app.

## A note on the shared-blob model

`crm_state.state` is one JSONB document per firm. That's the simplest thing that
fits how the current front-end works (it saves its whole state at once, debounced,
and Realtime keeps members in sync). It's great for a small practice.

Two people editing *the very same second* is last-write-wins. If you grow to
larger firms with heavy concurrent editing — or want per-record reporting and
permissions — the next step is splitting `crm_state` into relational tables
(`clients`, `deadlines`, `documents`, …) scoped by `firm_id`, and having the app
read/write rows. The firm/membership/RLS foundation here already supports that;
say the word and it can be migrated.
