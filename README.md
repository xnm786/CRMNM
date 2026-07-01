# Clera

A CRM for UK accountancy practices whose signature feature is an automated
"chasing engine" that follows up with clients for outstanding documents.

## What's in here

| File / dir | What it is |
|---|---|
| `index.html` | Marketing **landing page** |
| `index (2) - Copy (1).html` | The **CRM app** — a single-page app (dashboard, clients, leads, deadlines, document chasing, tasks, onboarding) wired to Supabase for auth, shared storage and AI |
| `supabase/` | The **backend**: SQL schema + Row-Level Security and the `ai-chase` Edge Function |

## Backend

The front-end talks to Supabase for auth, shared data persistence and AI.
Data belongs to a **firm**, so a whole practice's staff share one dataset (with
live sync and an invite flow), and the **AI onboarding agent** / chasing drafts
run through a Claude-powered Edge Function that keeps the API key server-side.

Everything needed to stand that up lives in [`supabase/`](./supabase). See
[`supabase/README.md`](./supabase/README.md) for setup steps and how firm sharing
works.
