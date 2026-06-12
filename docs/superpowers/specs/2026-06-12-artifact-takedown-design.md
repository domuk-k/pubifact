# Artifact takedown (delete) — design

**Date:** 2026-06-12
**Status:** approved, ready for implementation
**ROADMAP:** Phase 2 — "List / delete your own artifacts" (the *delete* half)

## Goal

pubifact can publish (`POST /up`) but has no way to take an artifact back down —
once published, the only recourse is a manual `wrangler r2 object delete`. This
adds a first-class **takedown** path so a publisher can remove what they put up,
operated entirely from the agent/skill.

## Security model — the third axis

DESIGN.md frames two security axes that gate different things:

- **`UPLOAD_TOKEN`** — who can *publish* (optional global bearer on `POST /up`).
- **per-link `password`** — who can *read* a page (salted SHA-256 in metadata).

This feature adds a third:

- **per-artifact `deleteToken`** — who can *take down* a page.

### How it works

- On **every** upload, mint `deleteToken = randomHex(16)` and store its salted
  SHA-256 in R2 `customMetadata` as `delhash` / `delsalt` — the exact
  `hashPw()` + `randomHex()` pattern the password feature already uses. The
  token is returned to the publisher **once** (see Upload response).
- To take down, the caller presents the token as `Authorization: Bearer
  <deleteToken>`. The worker re-hashes it against `delsalt` and compares to
  `delhash`.
- **Operator override:** if `UPLOAD_TOKEN` is set, presenting it as the bearer
  deletes *any* artifact — the self-host operator's master key.

### Trust-model notes

- The service defaults to **open** (`UPLOAD_TOKEN` usually unset). A per-artifact
  token protects takedown regardless of whether `UPLOAD_TOKEN` is configured;
  a global-token-only scheme would leave delete wide open in the default mode,
  and delete is destructive (unlike upload).
- Artifacts uploaded **before** this change have no `delhash`, so they are
  deletable only via the operator override. Acceptable; documented.
- `delhash`/`delsalt` coexist with `pwhash`/`pwsalt` when a page is also
  password-protected — independent keys in the same `customMetadata`.

## Worker changes (`worker/src/index.js`)

### Routing

Add `DELETE /:key` handling in `fetch()`, before the read (`GET`/`HEAD`) block:

```js
if (req.method === 'DELETE') return remove(req, env, url)
```

### `remove(req, env, url)`

1. `key = url.pathname.slice(1)`.
2. `obj = await env.BUCKET.head(key)` — metadata only, **no body fetch**.
   `404` (`not found\n`) if absent.
3. Extract the bearer token from `Authorization` (strip `Bearer `).
4. Authorize:
   - operator: `env.UPLOAD_TOKEN && token === env.UPLOAD_TOKEN`, OR
   - per-artifact: `delhash && token && (await hashPw(token, delsalt)) === delhash`
   - else `401` (`unauthorized`).
5. `await env.BUCKET.delete(key)`.
6. `await caches.default.delete(`${url.origin}/${key}`)` — evict the edge cache
   so a public takedown is immediate in the caller's region (public artifacts
   are `public, max-age=600`; password pages are already `no-store`).
7. Return `200`: `deleted\n` (text), or `{ deleted: key }` if
   `Accept: application/json`.

### Upload (`upload()`)

- Always mint `const deleteToken = randomHex(16)` and add
  `delsalt` / `delhash` to `putOpts.customMetadata` (merging with any
  `pwsalt`/`pwhash`, not overwriting).
- Return the token to the publisher:
  - **text mode:** line 1 = URL (unchanged), line 2 = `deleteToken`.
  - **JSON mode:** `{ url, deleteToken }`.

### CORS

`cors()` → `access-control-allow-methods: 'GET,POST,DELETE,OPTIONS'`.
(`authorization` is already in `access-control-allow-headers`.)

## Client changes (`skills/pubifact/publish.sh`)

### Publish path

- Capture both stdout lines from `/up`. Emit **URL to stdout** (line 1) — the
  existing contract is "stdout = the URL, capture the last line", so this must
  not change. Emit the **delete token to stderr** via `log()` as guidance
  (same channel as the existing password note), e.g.:
  `log "take it down later with: --down <url> --token <deleteToken>"`.

### New `--down` mode

- `publish.sh --down <url>` sends `DELETE <url>` with
  `Authorization: Bearer <token>`.
- Token source: `--token <tok>` flag, else `$PUBIFACT_DELETE_TOKEN`.
  (An operator may pass their `UPLOAD_TOKEN` as `--token`.)
- On success print `taken down` (stderr ok); surface `401` (wrong token) and
  `404` (already gone / unknown) distinctly. Missing token → usage error.

## Docs

- **SKILL.md:** add a "Taking it down" paragraph. Branding: speak in pubifact
  terms ("take it down" / "내렸습니다"), no R2/bucket/wrangler jargon. Note that
  the delete token prints to the logs (stderr) on publish, and is required to
  take the page down later.
- **DESIGN.md:** extend the "Two security axes" section to **three** (add the
  per-artifact `deleteToken` axis); remove `edit/delete` from "Out of scope".
- **ROADMAP.md Phase 2:** mark *delete* done, leave *list* unchecked with a
  one-line note that list needs an index-design decision (per-artifact tokens
  carry no publisher identity, so "list your own" isn't expressible yet).

## Verification

Against a local `wrangler dev` (or the live endpoint):

1. Publish a file → capture URL + delete token.
2. `GET` URL → `200`.
3. `DELETE` URL with the token → `200`.
4. `GET` URL → `404`.
5. Negative: `DELETE` with a wrong token → `401`.
6. Operator: with `UPLOAD_TOKEN` set, `DELETE` a (no-`delhash`) artifact using
   the upload token → `200`.

Use the `curl -s -o /dev/null -w "%{http_code}"` pattern for status assertions.

## Out of scope (this change)

- **List** endpoint — deferred; needs an indexing model to express "your own".
- TTL / auto-expire, custom slugs, in-place update — separate Phase 2 items.

## Pre-step

The repo is not git-initialized. `git init` is required before the first commit;
confirm with the user before committing.
