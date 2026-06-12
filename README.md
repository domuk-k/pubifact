# pubifact

[![CI](https://github.com/domuk-k/pubifact/actions/workflows/ci.yml/badge.svg)](https://github.com/domuk-k/pubifact/actions/workflows/ci.yml)
[![MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Turn a static HTML or Markdown file into a shareable URL with one command — for
any AI coding agent (Claude Code, OpenCode, Codex, …). Markdown is rendered to
a clean HTML page.

```
"publish foo.html"             →  https://pubifact.<you>.workers.dev/x7qk2abc.html
"publish notes.md"             →  rendered to HTML at the same kind of URL
"publish secret.md --password" →  same, but viewers must enter the password
```

Two pieces:

| Piece | What | Where |
|-------|------|-------|
| **skill** | The thin client an agent runs (`publish.sh` + `SKILL.md`). Reads config, prompts you to run `init.sh` if none is set. | [`skills/pubifact/`](skills/pubifact/) |
| **worker** | A free `POST file → URL` service: Cloudflare Worker + R2, renders Markdown. | [`worker/`](worker/) |

See [`DESIGN.md`](DESIGN.md) for the why.

## Use the skill

Install it for your agent (Claude Code example — personal skills apply to every
project):

```bash
npx skills add domuk-k/pubifact
```

Then ask your agent to "publish this" or "share this page". That's it.

**How the first publish works — init-first.** On the first publish the skill
detects that no instance is configured and offers to set up your own free
permanent instance (~2 minutes). No content is uploaded to any third-party host
— your data only ever reaches your own infrastructure.

Alternatively, install by hand with a symlink:

```bash
ln -s "$PWD/skills/pubifact" ~/.claude/skills/pubifact
```

## Set up your own backend (free, permanent)

One-time, ~3 minutes. Needs a free Cloudflare account. The skill's `init.sh`
walks you through it:

```bash
bash ~/.claude/skills/pubifact/init.sh setup
```

Or click the button below (no CLI needed):

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/domuk-k/pubifact/tree/main/worker)

<!-- TODO: verify button resolves worker/ subdir + R2 auto-provision after repo is public -->

After either path, add your endpoint and token to the config file:

```json
{
  "endpoint": "https://pubifact.<account>.workers.dev",
  "token": "<your-upload-token>"
}
```

Default location: `~/.config/pubifact/config.json` (written automatically by
`init.sh`; the `token` key is only needed if you set `UPLOAD_TOKEN` on the
worker).

Environment variables override the config file (advanced / CI use):

```bash
export PUBIFACT_ENDPOINT=https://pubifact.<account>.workers.dev
export PUBIFACT_TOKEN=<your-upload-token>
```

## What init.sh does, step by step

If you prefer to do it by hand:

```bash
cd worker
npm install
npx wrangler login                         # opens browser, authorize
npx wrangler r2 bucket create pubifact     # create the storage bucket
npx wrangler deploy                        # deploy the Worker — prints your URL
```

Recommended hardening:

```bash
npx wrangler secret put UPLOAD_TOKEN       # require a bearer token on uploads
```

Then write `~/.config/pubifact/config.json` with your endpoint and token.

### Cost

Cloudflare free tier covers small usage at ~$0: Workers 100k requests/day, R2
10 GB storage and **zero egress fees** (ideal for serving HTML).

## Worker API

| Method & path | Purpose |
|---------------|---------|
| `POST /up` | Publish. Body: multipart `file` (preferred) or raw bytes. Returns two text lines — the URL, then a one-time **delete token** — or JSON (`url`, `deleteToken`) if `Accept: application/json`. |
| `GET /:key` | Serve the page as `text/html`. 404 if unknown. |
| `HEAD /:key` | Headers only (for link unfurlers). |
| `DELETE /:key` | Take the page down. `Authorization: Bearer <delete-token>` (or the operator's `UPLOAD_TOKEN` as master key). |

`POST /up` fields / params:

- `file` — the artifact. `.md`/`.markdown` filenames are rendered to HTML;
  for a raw body use `?type=md` and optionally `?name=foo.md`.
- `password` — optional. If set, the page requires it to view (HTTP Basic, any
  username; or `?k=<password>`). Protected pages send `Cache-Control: private`.
- Size cap: 5 MB. If `UPLOAD_TOKEN` is configured, send `Authorization: Bearer <token>`.

```bash
curl -F file=@page.html https://<your>.workers.dev/up
curl -F file=@notes.md -F password=hunter2 https://<your>.workers.dev/up

# take it down later (token = line 2 of the publish response)
curl -X DELETE -H "Authorization: Bearer <delete-token>" https://<your>.workers.dev/x7qk2abc.html
# or from the skill:
bash skills/pubifact/publish.sh --down <url> --token <delete-token>
```

The delete token is shown **once**, at publish time. A page published before
this feature existed can only be removed with the operator's `UPLOAD_TOKEN`.

## Caveats

- Pages are hosted on a **public host**; without `--password` anyone with the
  link can open it and its JS runs. Use `--password` for private content.
- `--password` gates *reading* (good for "share with specific people"). It is
  **not** a fit for NDA/regulated data: content still lives in your R2, and the
  gate is only as strong as the password. Keep contractually-restricted material
  in sanctioned infra.
- An open upload endpoint can be abused; flip on `UPLOAD_TOKEN`, the 5 MB cap,
  or Cloudflare rate-limiting if needed.
- Artifacts must be self-contained — inline assets, no relative file refs.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md) for the trust model and how to report
vulnerabilities.

## License

MIT
