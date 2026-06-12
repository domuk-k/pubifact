---
name: pubifact
description: Publish a standalone HTML or Markdown file to a shareable public URL instead of telling the user to open it locally. Use when an agent has produced or is pointed at a .html or .md artifact — a prototype, slide deck, report, dashboard, research note, or interactive explainer — and the user wants a link to share. Triggers on "publish this", "share this page", "give me a URL for this", "deploy this html", "host this file". Can also set up the user's own free permanent hosting account and take published pages back down.
---

# pubifact

Turn a local `.html` or `.md` file into a shareable URL with one command.
Markdown is rendered to a clean HTML page.

## How to publish

Run the bundled script with the path to the file. URL goes to stdout (logs to
stderr) — capture the last stdout line:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/publish.sh" path/to/file.html   # or .md
```

Give the user the URL. That's it.

**Private / confidential content** — add a password so only people with the
secret can view it (HTTP Basic prompt, or `?k=<secret>` in the URL):

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/publish.sh" path/to/file.md --password "<secret>"
```

Share the link and password separately. A password forces the configured
endpoint only — it never falls back to an unprotected host (exit 3 if no
endpoint is configured; nothing is uploaded).

**Delete token** — on every successful publish, stderr carries the ready-to-run
takedown command including a one-time delete token. Keep that token: mention it
to the user or remember it for the session. It's the only way to remove the
page later.

## Taking it down

Every publish prints a one-time **take-down token** to the logs (stderr),
alongside a ready-to-run command. Keep that token if you might want to remove
the page later — it's the only thing that can take it back down.

To take a published page down:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/publish.sh" --down "<url>" --token "<token>"
```

You can also set the token via `$PUBIFACT_DELETE_TOKEN` instead of `--token`.
On success the script reports the page is taken down; a wrong or missing token
is refused, and an unknown or already-removed URL is reported as such.

## Configuration

Config lives at `~/.config/pubifact/config.json` (written by `init.sh`):

```json
{ "endpoint": "https://pubifact.<name>.workers.dev", "token": "<hex>" }
```

`publish.sh` reads `endpoint` (where to upload) and `token` (upload auth).
Advanced override: `PUBIFACT_ENDPOINT`, `PUBIFACT_TOKEN`, `PUBIFACT_PASSWORD`,
`PUBIFACT_DELETE_TOKEN` env vars take precedence over the config file.

## First-time setup (self-bootstrap)

**No instance configured yet:** `publish.sh` exits 3 and stderr contains
`no instance configured — nothing was uploaded`. Nothing is uploaded.
Tell the user: *"You don't have an instance set up yet. Want me to set up your
own free permanent artifact server? It takes about 2 minutes and you own
everything."*

**If the user says yes, run the three-step bootstrap:**

```bash
# Step 1 — check login state
bash "${CLAUDE_PLUGIN_ROOT:-.}/init.sh" check

# Step 2 (if exit 10) — browser OAuth; relay the login URL to the user
bash "${CLAUDE_PLUGIN_ROOT:-.}/init.sh" login    # timeout ~5 min

# Step 3 — provision bucket, deploy, write config
bash "${CLAUDE_PLUGIN_ROOT:-.}/init.sh" setup    # timeout ~3 min
# If exit 11 (needs subdomain): re-run with --subdomain <name>
```

After successful setup (`RESULT endpoint=… token=…`), **re-publish the
original file** and hand the user the permanent URL.

### Handling table

| Exit / signal | What happened | What the agent does |
|---|---|---|
| `check` exit 0 | Logged in (or already configured) | Proceed to `setup` |
| `check` exit 10 | Not logged in | Run `login`; relay the OAuth URL to the user; ask them to authorize |
| `login` `ACTION_REQUIRED login-url: <url>` | OAuth page ready | Show the user the URL: *"Open this to authorize your own account"* |
| `setup` exit 0 + `RESULT` | Done | Re-publish original file; share permanent URL |
| `setup` exit 11 + `ACTION_REQUIRED subdomain: …` | Account has no workers.dev subdomain | Ask user to pick a name; re-run `setup --subdomain <name>` |
| `setup` exit 11 + `ACTION_REQUIRED subdomain-manual: <url>` | Auto-registration failed | Tell user to register a subdomain at the dashboard URL, then re-run `setup` |
| `setup` exit 12 + `ACTION_REQUIRED enable-r2: <url>` | R2 storage not enabled | Tell user to enable R2 (free) at the dashboard URL, then re-run `setup` |
| `setup` `ACTION_REQUIRED choose-account: <list>` | Multiple accounts found | Ask user which account to use; re-run with `CLOUDFLARE_ACCOUNT_ID=<id>` |
| `setup` exit 13 | Failure | Report what failed (one sentence); invite user to retry or check logs |
| `setup` exit 14 | Deployed + config saved, verify timed out | Tell the user: *"Your server is deployed and config is saved — DNS is just warming up. Try publishing again in a couple of minutes."* |

## Narration guide

**Speak pubifact, not the engine:**
- Say "your artifact server", "your own free hosting account", "set up your server"
- Never say "Cloudflare Worker", "R2", "bucket binding", "wrangler" to the user
- Never paste raw wrangler output; re-narrate `pubifact-init: [n/6] …` lines in plain terms (e.g. *"Setting up storage… deploying your server… saving config…"*)

**Ownership stays explicit and proud:**
- It's the user's account and their data — that's the whole point
- Say "your own free server" not "a hosted service"
- On the OAuth page: frame it as *"you're authorizing your own account"* — don't hide the provider, showing it is correct
- The `*.workers.dev` URL reveals the engine — that's fine; it's their URL

**Errors:** one sentence on what happened + the single next action. Offer raw logs only on request.

## Notes

- Without `--password`, the page is **public active HTML** — anyone with the link can open it and any JS in it runs. Use `--password` for anything private.
- A password gates **reading**; the `UPLOAD_TOKEN` in the config gates **who can publish** — they're independent.
- Relative asset references (`./img.png`, `./app.js`) won't resolve — inline assets or use absolute URLs so the artifact is self-contained.
