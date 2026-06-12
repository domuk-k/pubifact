# Changelog

All notable changes to this project will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/) — major bumps signal a breaking
change to the `POST /up` / `GET /:key` API or the `publish.sh` CLI contract.

## [Unreleased]

### Added
- Per-artifact takedown: every publish mints a one-time delete token
  (line 2 of the plain-text response, `deleteToken` in JSON mode);
  `DELETE /:key` with `Authorization: Bearer <token>` removes the page.
  The operator's `UPLOAD_TOKEN` doubles as a master-key override.
  Client side: `publish.sh --down <url> --token <tok>`.
- Config file `~/.config/pubifact/config.json` (`endpoint`, `token` keys);
  `publish.sh` reads it with env vars as override.
- `init.sh` — agent-driven self-hosting bootstrap (wraps wrangler, narrates in
  pubifact terms).
- Init-first onboarding: first publish without config exits 3 and offers to
  deploy a permanent instance via `init.sh` (replaces the removed tmpfiles
  fallback — see Changed).
- Worker migrated to TypeScript; `worker/src/lib.ts` extracts pure helpers.
- Vitest + `@cloudflare/vitest-pool-workers` integration tests for the worker.
- bats integration tests for `publish.sh` and `init.sh`.
- GitHub Actions CI (worker lint/typecheck/test + shell shellcheck/shfmt/bats).

### Changed
- `POST /up` plain-text response is now two lines — line 1 the URL, line 2 the
  delete token. Capture line 1 if you only want the URL.
- The skill no longer defaults to a shared reference instance.
- `publish.sh` switched to **init-first**: no instance configured → exit 3 +
  stderr `no instance configured — nothing was uploaded` + path to `init.sh`.
  The previous tmpfiles.org fallback is removed. Reason: tmpfiles rejected
  HTML/Markdown files unpredictably ("Invalid file name/type") and uploaded
  content to a third-party host with no ownership guarantee. Exit codes
  clarified: 0 success · 1 instance unreachable/publish failed · 2 usage ·
  3 no instance configured (run init.sh) · 4 auth or size error.

## [0.1.0] - 2026-06-10

Initial release (Phase 0).

### Added
- Cloudflare Worker + R2 backend (`worker/`): `POST /up` stores a file under a
  random 8-char slug and returns the URL; `GET|HEAD /:key` serves it.
- Markdown → HTML rendering (server-side, via `marked`).
- Per-link password protection: salted SHA-256, enforced on `GET` via HTTP Basic
  or `?k=` query param; protected pages are `Cache-Control: private, no-store`.
- Optional `UPLOAD_TOKEN` bearer gate on `POST /up`.
- 5 MB upload cap (413 on exceed).
- `pubifact` agent skill (`skills/pubifact/publish.sh` + `SKILL.md`) —
  installable via `npx skills add domuk-k/pubifact` or `ln -s`.
- Fallback to tmpfiles.org when no endpoint is configured and no password given.
