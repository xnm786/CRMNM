# Clera backend (Supabase)

The Clera CRM front-end (`index (2) - Copy (1).html`) is wired to **Supabase**
for three things. This directory is the backend that satisfies that contract.

| What the app does | Backend piece |
|---|---|
| Sign in / create account (`sb.auth.signUp` / `signInWithPassword`) | **Supabase Auth** — no code needed, just enable email/password |
| Save & load the whole CRM (`sb.from('crm_state').upsert(...)` / `.select(...)`) | **`crm_state` table** + Row-Level Security — `migrations/0001_init.sql` |
| Draft chasing emails / answer questions (`sb.functions.invoke('ai-chase', { body:{ prompt } })`) | **`ai-chase` Edge Function** — `functions/ai-chase/` |
| Landing-page waitlist sign-ups (`index.html`) | **`waitlist` table** — `migrations/0001_init.sql` |

The Supabase project URL and anon key are already in both HTML files. The anon
key is meant to be public — it is safe to ship **because** Row-Level Security is
enabled by the migration below. Do not put the *service role* key in the
front-end.

## 1. Prerequisites

```bash
npm install -g supabase        # the Supabase CLI
supabase login
supabase link --project-ref vhkzpzebsnlworotwyfg   # your project ref (from the URL)
```

## 2. Create the tables + security policies

```bash
supabase db push
```

(Or open the Supabase dashboard → SQL editor and paste
`migrations/0001_init.sql`.)

This creates `crm_state` and `waitlist`, turns on RLS, and adds policies so each
user can only touch their own CRM data while anyone can still join the waitlist.

## 3. Enable email/password auth

Dashboard → **Authentication → Providers → Email** → enable it. For a smooth
demo you can also turn *off* "Confirm email" so `Create account` logs the user
straight in (the app shows a "check your email" message when confirmation is on).

## 4. Deploy the AI function

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...   # your Anthropic key
supabase functions deploy ai-chase
```

Optionally pin a cheaper model for high-volume chasing:

```bash
supabase secrets set CLERA_AI_MODEL=claude-haiku-4-5
```

The function keeps the API key server-side and returns `{ text: "..." }`. If it
is ever unreachable or unconfigured, the front-end automatically falls back to a
local template, so the app never breaks.

## 5. Run it

Open either HTML file in a browser. Because the Supabase URL and anon key are
already filled in, the app runs in "live" mode: it shows the sign-in gate,
persists to `crm_state`, and calls `ai-chase` for AI features. (Blank the keys
to run the in-memory demo instead.)

## Data model note

`crm_state.state` is a single JSONB document holding the user's clients,
deadlines, documents, tasks, leads and onboarding — the app treats its whole
state as one object and saves it wholesale (debounced). That's the simplest
thing that matches the current front-end. If you later want per-record querying,
reporting, or multi-user practices sharing one dataset, the natural next step is
to split this into relational tables (`clients`, `deadlines`, `documents`, …) and
have the app read/write rows instead of one blob — happy to do that when needed.
