# Design

## Goal

An agent (Claude Code / OpenCode / Codex) often produces a standalone HTML
artifact — a prototype, slide deck, report, or interactive explainer. Today the
agent says "open the file locally". We want a **repeatable, ultra-simple way to
get a shareable URL** that anyone can use with minimal setup, free.

## Why not just Vercel/Netlify/surge

Those are vendor-specific and assume the user has an account on that platform.
For a skill meant to be distributed (e.g. skills.sh) to arbitrary users, the
binding constraint is **zero new signups** and **no vendor lock-in**. The first
draft of this work over-fit to one company's Vercel team; this design corrects
that.

## Two layers

### 1. Skill (client) — `skills/pubifact/`

A thin, agent-runnable script encoding a decision tree so the behavior is
identical across agents:

1. **Configured endpoint** (`~/.config/pubifact/config.json` or env var) — your
   own Cloudflare Worker. Persistent, clean URL, fully under your control.
2. **tmpfiles.org** — no account, ephemeral (~1h). Fallback so the skill is
   usable before a backend is deployed; the skill offers to set one up.

> An earlier draft also tried a GitHub gist + githack render proxy. Dropped: it
> binds links to an individual's GitHub account, depends on a third-party proxy
> we don't control, and produces ugly URLs — it isn't "our service".

Markdown (`.md`) is rendered to HTML by the backend, so research notes and
reports become readable pages, not raw text.

### 2. Backend (operated) — `worker/`

A free `POST html → URL` service so the simplest path needs **no user account
at all** — just `curl -F file=@x.html $ENDPOINT/up`.

**Infra: Cloudflare Worker + R2.** Chosen over a home-server + tunnel:

| | CF Worker + R2 | Home server + ngrok/cloudflared |
|---|---|---|
| Cost at small scale | ~$0 (free tier; R2 egress free) | hardware + power, "free-ish" |
| Uptime | global, managed | home internet / box availability |
| Abuse / DDoS | Cloudflare absorbs | your home IP is the target |
| Custom domain | trivial | needs setup |
| Ops | none | patch / babysit the box |

The home-server idea is kept only as a *self-host / dev* mode, not the public
backend.

**Endpoints:**
- `POST /up` — multipart `file` (or raw body) → R2 under a random 8-char slug →
  returns the URL (plain text, or JSON if `Accept: application/json`). Markdown
  is rendered to HTML; an optional `password` field read-protects the page.
- `GET|HEAD /:key` — stream from R2 with `content-type: text/html` so it renders;
  enforces the password if one was set.
- `GET /` — usage page.

## Three security axes (don't conflate)

They gate different things; each can be on independently:

- **`UPLOAD_TOKEN` — who can *publish*.** Bearer gate on `POST /up`. Off by
  default (zero-setup); flip on to stop abuse when the instance is public.
- **per-link `password` — who can *read* a page.** Set at upload; stored as a
  salted SHA-256 in object metadata; enforced on GET via HTTP Basic (or `?k=`).
  Protected pages are `Cache-Control: private, no-store`.
- **per-artifact `deleteToken` — who can *take down* a page.** Minted on every
  upload, returned to the publisher once, and stored as a salted SHA-256
  (`delsalt`/`delhash`) alongside any password hash. Presented as a bearer on
  `DELETE /:key`. `UPLOAD_TOKEN`, if set, is an operator override that can take
  down any artifact. Delete defaults to closed (a token is always required),
  because it is destructive — unlike upload, which defaults open.

## Read trust model

Without a password we host **arbitrary active HTML** (interactive explainers
ship JS), so a script-blocking CSP is off the table — it would defeat the
purpose. Same trust model as surge / neocities / codepen. Mitigations:

- Serve from the cookie-less `workers.dev` origin → no cookie/session to steal.
- `X-Content-Type-Options: nosniff`, 5 MB size cap.
- Future: Cloudflare rate-limiting / Turnstile, R2 lifecycle auto-expiry.

A password protects casual access, but the bytes still live in R2 (a
third-party host) — so this is **not** a control for NDA/regulated data, only
for "share with specific people". Documented in the README caveats.

## Out of scope (YAGNI for v1)

- Custom slugs / vanity URLs, in-place edit, dashboards, accounts.
  (Per-artifact **delete** is now in scope — see the third security axis above.)
- Multi-file bundles (publish each file; stage an `index.html` if needed).
- Analytics, auth beyond the optional token.

## Status

- Skill + worker implemented and verified end-to-end (local + live).
- Skill installable via `npx skills add domuk-k/pubifact` and laid out as
  `skills/pubifact/SKILL.md`.
- Onboarding: lazy bootstrap (first publish via tmpfiles fallback, then offer to
  deploy your own permanent instance via `init.sh`).
- Remaining for public release: push to a public GitHub repo.
