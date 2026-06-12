# pubifact

Turn a static HTML or Markdown file into a shareable URL with one command — for
any AI coding agent (Claude Code, OpenCode, Codex, …). Zero account setup for the
end user. Markdown is rendered to a clean HTML page.

```
"publish foo.html"            →  https://pubifact.<you>.workers.dev/x7qk2abc.html
"publish notes.md"            →  rendered to HTML at the same kind of URL
"publish secret.md --password" →  same, but viewers must enter the password
```

Two pieces:

| Piece | What | Where |
|-------|------|-------|
| **skill** | The thin client an agent runs (`publish.sh` + `SKILL.md`). Posts to the hosted endpoint, falls back to tmpfiles. | [`skills/pubifact/`](skills/pubifact/) |
| **worker** | A free `POST file → URL` service: Cloudflare Worker + R2, renders Markdown. | [`worker/`](worker/) |

See [`DESIGN.md`](DESIGN.md) for the why.

## Use the skill

Install it for your agent (Claude Code example — personal skills apply to every
project):

```bash
ln -s "$PWD/skills/pubifact" ~/.claude/skills/pubifact
```

The script already defaults to a reference instance, so it works out of the box.
To point at **your own** backend instead, set:

```bash
export PUBIFACT_ENDPOINT=https://pubifact.<account>.workers.dev
```

Then just ask your agent to "publish this", or run it directly:

```bash
bash skills/pubifact/publish.sh page.html               # or notes.md
bash skills/pubifact/publish.sh secret.md --password X   # private: prompts to view
```

If the endpoint is unreachable (and no password was given) it falls back to
tmpfiles.org with a temporary link, so the skill is still usable.

## Run the backend (free)

One-time, ~3 minutes. Needs a free Cloudflare account.

```bash
cd worker
npm install
npx wrangler login                         # opens browser, authorize
npx wrangler r2 bucket create pubifact  # create the storage bucket
npx wrangler deploy                         # deploy the Worker
```

`wrangler deploy` prints your URL: `https://pubifact.<account>.workers.dev`.
Put that in `PUBIFACT_ENDPOINT` and you're done.

Optional hardening (see `worker/wrangler.jsonc`):

- `npx wrangler secret put UPLOAD_TOKEN` — require a bearer token on uploads.
- R2 lifecycle rule — auto-expire old pages.

### Cost

Cloudflare free tier covers small usage at ~$0: Workers 100k requests/day, R2
10 GB storage and **zero egress fees** (ideal for serving HTML).

## Worker API

| Method & path | Purpose |
|---------------|---------|
| `POST /up` | Publish. Body: multipart `file` (preferred) or raw bytes. Returns the URL as text, or JSON if `Accept: application/json`. |
| `GET /:key` | Serve the page as `text/html`. 404 if unknown. |
| `HEAD /:key` | Headers only (for link unfurlers). |

`POST /up` fields / params:

- `file` — the artifact. `.md`/`.markdown` filenames are rendered to HTML;
  for a raw body use `?type=md` and optionally `?name=foo.md`.
- `password` — optional. If set, the page requires it to view (HTTP Basic, any
  username; or `?k=<password>`). Protected pages send `Cache-Control: private`.
- Size cap: 5 MB. If `UPLOAD_TOKEN` is configured, send `Authorization: Bearer <token>`.

```bash
curl -F file=@page.html https://<your>.workers.dev/up
curl -F file=@notes.md -F password=hunter2 https://<your>.workers.dev/up
```

## Caveats

- Pages are hosted on a **public host**; without `--password` anyone with the
  link can open it and its JS runs. Use `--password` for private content.
- `--password` gates *reading* (good for "share with specific people"). It is
  **not** a fit for NDA/regulated data: content still lives in your R2 (a
  third-party host) and the gate is only as strong as the password. Keep
  contractually-restricted material in sanctioned infra.
- An open upload endpoint can be abused; flip on `UPLOAD_TOKEN`, the 5 MB cap,
  or Cloudflare rate-limiting if needed.
- Artifacts must be self-contained — inline assets, no relative file refs.

## License

MIT
