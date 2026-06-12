# pubifact — Roadmap

## What it is

**Agent-native, self-hostable artifact (HTML / Markdown) hosting.** Your coding
agent (Claude Code / Codex / OpenCode) publishes an artifact to a shareable URL —
served from **your own** infrastructure. The brand surface is **pubifact**; the
engine (Cloudflare) stays under the hood.

> "A personal artifact server, operated entirely from your agent."

## Positioning / moat

The generic "AI HTML → instant URL" space is a red ocean — Handoff, PageDrop,
HTML Pub (MCP), backrun — all **closed, hosted SaaS**. pubifact does not compete
there. The wedge they structurally cannot copy:

- **No trust hand-off (BYOK)** — every competitor says "upload to *our* server."
  pubifact's artifacts live on *your* infra; there is no third party to trust.
- **Unlocks confidential artifacts** — internal / NDA / client-confidential work
  you'd never upload to someone else's host, shared from your own instance + a
  password. The killer use case external servers can't serve.
- **Agent-portable** — a plain skill, any agent, no lock-in.
- **Pay-it-forward OSS** — MIT, free, self-host-first.

## Business model

**Open-core. Monetization is parked** until there are real users asking. Free +
OSS + self-host-first. Data sovereignty always stays with the user. Future
freemium hooks (custom domain, central vanity domain, teams) are noted in
Phase 4 — *not built now*.

## Branding principle (end-UX)

- **Surface = pubifact.** Hide engine jargon (wrangler / R2 / "bucket binding")
  from user-facing messages, commands, and docs. `init` wraps `wrangler`
  silently; the agent narrates in pubifact terms; wrangler errors are re-narrated.
- **But keep ownership transparent** — "this is *your* account, *your* data" is
  the moat; never hide it. Say *"your own free server,"* not *"a Cloudflare
  Worker + R2 bucket."*
- **Two unavoidable leaks — handled, not hidden:**
  1. The OAuth login page shows the provider — it's *your* account, so showing it
     is correct (hiding it would read as sketchy). Frame it, don't mask it.
  2. The `*.workers.dev` URL reveals the provider — white-label via *your own*
     custom domain (opt-in, Phase 3).

## Personas

- **P1 — publisher (primary):** AI-coding dev (CC / Codex). Generates artifacts,
  wants a link. Can self-host once.
- **P2 — recipient:** PM / designer / stakeholder. Only clicks the link. Needs it
  to look legit and load instantly. Never self-hosts.

## Architecture decisions

- **Default = BYOK Cloudflare Worker + R2** — your account, persistent, a clean
  trustworthy URL, free tier, no machine dependency.
- **Tunnels are cut** — `trycloudflare`-style URLs get flagged / blocked by
  corporate filters and look sketchy to recipients, which kills the core value
  (the recipient must open the link). Ephemeral ≠ tunnel.
- **Short-lived artifacts → Worker + TTL** (auto-expire) on a clean URL. You get
  "short-lived" *and* "trustworthy URL" — tunnels can't.
- **Config = `~/.config/pubifact/config.json`** (`endpoint`, `token`). Not an env
  var. Set once, portable across agents; `publish` reads it, `init` writes it.
- **`init` = skill-bundled `init.sh`**, agent-driven (manual run also works). Not
  an npm package, not brew, not a CC-only slash command (would break portability).

## Onboarding (two paths — both BYOK, both land at "your own instance")

- **Agent users (P1):** `npx skills add <owner>/pubifact` → on the first
  "publish this", the skill detects no instance is configured and offers to
  deploy your own permanent instance (`init.sh`, ~2 min). Your data never
  touches a third-party host — init-first, always your infra.
- **Anyone / non-CLI:** a **"Deploy to Cloudflare" button** in the README →
  clone-to-your-account + auto-provision R2 + deploy, no CLI, no agent.

---

## Phases

### Phase 0 — ✅ Done
Worker + R2 backend · Markdown→HTML render · per-link password · optional
`UPLOAD_TOKEN` · 5 MB cap · the `pubifact` skill (`skills/pubifact/` layout,
installed) · docs · a live reference instance *(retired in Phase 1)* ·
tmpfiles.org fallback *(removed in Phase 1 — rejected HTML/Markdown
unpredictably and leaked content to a third-party host)*.

### Phase 1 — OSS + BYOK + seamless onboarding  *(next)*
- [ ] **Retire the shared reference instance**; remove the silent central default.
- [ ] **Config file** `~/.config/pubifact/config.json` — `publish` reads, `init`
      writes.
- [ ] **`init.sh`** — agent-driven, wrangler-wrapped, **narration-abstracted**
      (pubifact terms, wrangler output hidden, errors re-narrated, ownership kept
      transparent).
- [ ] **Init-first onboarding** — first publish without an instance → offer to
      deploy your own (init.sh); no fallback to third-party hosts.
- [ ] **"Deploy to Cloudflare" button** + **public GitHub repo** + skills.sh
      (`npx skills add`).
- [ ] **SKILL.md** — branding / narration guidance for the agent.
- **Done when:** a stranger installs the skill (or clicks the button), gets their
  own instance, and publishes a clean URL — never touching ours, never seeing
  wrangler jargon.

### Phase 2 — File-server core
- [ ] **TTL / auto-expire** (`--ttl`) for short-lived artifacts.
- [x] **Delete** your own artifacts — per-artifact take-down token (minted on
      every publish), with an operator override via `UPLOAD_TOKEN`.
- [ ] **List** your own artifacts — needs an index-design decision first:
      per-artifact tokens carry no publisher identity, so "list *your own*" is
      not expressible yet without an ownership/indexing model.
- [ ] (maybe) custom slug / in-place update (re-publish to the same URL).
- **Done when:** you can see, expire, delete, and refresh what you've published.

### Phase 3 — Polish + white-label  *(P2)*
- [ ] **Preview cards** (OG / Twitter meta) — links unfurl nicely in chat.
- [ ] **Custom domain** (your own) — full URL white-label, hides the engine.
- [ ] Rendered-output quality pass.
- **Done when:** a shared link looks polished and fully branded.

### Phase 4 — Parking lot  *(only on real demand / eventual freemium)*
- Central vanity domain `*.pubifact.app` via **Cloudflare for SaaS** — data stays
  in the user's R2 (moat intact); only the domain is central.
- Team spaces · analytics · retention / large-file tiers.

## Non-goals (now)
Monetization / payments · multi-tenant SaaS storing strangers' content · user
accounts · tunnels.

## Guiding principle
Every feature must keep the moat: **self-hostable, agent-portable, your-data-your-
infra, no lock-in.** If it only works on central infra we operate → Phase 4
(parked), not core. End-UX speaks pubifact; ownership stays transparent.
