# pubifact

[![CI](https://github.com/domuk-k/pubifact/actions/workflows/ci.yml/badge.svg)](https://github.com/domuk-k/pubifact/actions/workflows/ci.yml)
[![MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Cloudflare Workers](https://img.shields.io/badge/Cloudflare-Workers-F38020?logo=cloudflare&logoColor=white)](https://workers.cloudflare.com/)

> **Agent-native artifact hosting** — publish HTML or Markdown to a shareable URL on your own Cloudflare Worker. One command from Claude Code, Codex, or any agent with the skill installed.

```
"publish report.html"  →  https://pubifact.<you>.workers.dev/x7qk2abc.html
"publish notes.md"     →  rendered HTML at the same URL shape
"publish draft.md --password secret"  →  password-gated page
```

Your content never touches a third-party host — only **your** R2 bucket and Worker.

---

## Two pieces

| Piece | Role |
|-------|------|
| [**skill**](skills/pubifact/) | Thin client: `publish.sh` + `SKILL.md`. Agents call it on "publish this". |
| [**worker**](worker/) | `POST file → URL` API on Cloudflare Workers + R2. Renders Markdown → HTML. |

Design rationale: [`DESIGN.md`](DESIGN.md)

---

## Use the skill (30 seconds)

```bash
npx skills add domuk-k/pubifact
```

Then ask your agent: *"publish this HTML"* or *"share this page"*.

**First run:** if no instance is configured, the skill offers a ~2-minute setup for your own free permanent Worker. No upload happens until you own the endpoint.

Manual install:

```bash
ln -s "$PWD/skills/pubifact" ~/.claude/skills/pubifact
```

---

## Set up your backend (~3 min)

Needs a free [Cloudflare](https://dash.cloudflare.com) account.

```bash
bash ~/.claude/skills/pubifact/init.sh setup
```

Or one-click deploy:

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/domuk-k/pubifact/tree/main/worker)

Config written to `~/.config/pubifact/config.json`:

```json
{
  "endpoint": "https://pubifact.<account>.workers.dev",
  "token": "<upload-token-if-set>"
}
```

### Manual deploy

```bash
cd worker && npm install
npx wrangler login
npx wrangler r2 bucket create pubifact
npx wrangler deploy
npx wrangler secret put UPLOAD_TOKEN   # recommended
```

**Cost:** Cloudflare free tier — Workers 100k req/day, R2 ~10 GB, **zero egress** for HTML serving.

---

## Worker API

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/up` | Publish file → URL + one-time delete token |
| `GET` | `/:key` | Serve page (`text/html`) |
| `HEAD` | `/:key` | Link unfurlers |
| `DELETE` | `/:key` | Remove page (`Authorization: Bearer <delete-token>`) |

```bash
curl -F file=@page.html https://<your>.workers.dev/up
curl -F file=@notes.md -F password=hunter2 https://<your>.workers.dev/up
```

Markdown (`.md`), size cap 5 MB, optional `UPLOAD_TOKEN` on uploads.

---

## Security notes

- Public URLs are **world-readable** unless `--password` is set.
- Password gates viewing; not for regulated/NDA data — use sanctioned infra for that.
- Enable `UPLOAD_TOKEN` + rate limits on public deployments.
- Artifacts must be self-contained (inline assets; no relative file refs).

See [SECURITY.md](SECURITY.md) for the full trust model.

---

## Related

- [domuk-k](https://github.com/domuk-k) agent infrastructure
- [oh-my-workflow](https://github.com/domuk-k/oh-my-workflow) — orchestrate agents that produce artifacts to publish
- Cloudflare skill: `wrangler`, `workers-best-practices`

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT