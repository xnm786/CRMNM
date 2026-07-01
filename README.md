# Clera

A CRM for UK accountancy practices whose signature feature is an automated
"chasing engine" that follows up with clients for outstanding documents.

## What's in here

| File / dir | What it is |
|---|---|
| `index.html` | Marketing **landing page** with a Supabase-backed waitlist form |
| `index (2) - Copy (1).html` | The **CRM app** itself — a single-page app (dashboard, clients, leads, deadlines, document chasing, tasks, onboarding) wired to Supabase for auth, storage and AI |
| `supabase/` | The **backend**: SQL schema + Row-Level Security and the `ai-chase` Edge Function |

## Backend

The front-end talks to Supabase for auth, data persistence, the AI chasing
engine, and waitlist sign-ups. Everything needed to stand that up — the database
schema, security policies, and the Claude-powered Edge Function — lives in
[`supabase/`](./supabase). See [`supabase/README.md`](./supabase/README.md) for
setup steps.
