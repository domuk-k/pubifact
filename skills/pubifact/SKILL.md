---
name: pubifact
description: Publish a standalone HTML or Markdown file to a shareable public URL instead of telling the user to open it locally. Use when an agent has produced or is pointed at a .html or .md artifact — a prototype, slide deck, report, dashboard, research note, or interactive explainer — and the user wants a link to share. Triggers on "publish this", "share this page", "give me a URL for this", "deploy this html", "host this file".
---

# pubifact

Turn a local `.html` or `.md` file into a shareable URL with one command.
Markdown is rendered to a clean HTML page. Works for anyone with zero account
setup — it posts to a hosted endpoint, falling back to a no-account host.

## When to use

The user has a self-contained artifact — an HTML prototype/slides/dashboard, or
a Markdown report/research note — and wants to **share a link** rather than
"open the file locally". Common right after an agent generates the artifact.

## How to publish

Run the bundled script with the path to the file. It prints the URL to stdout
(logs go to stderr), so capture the last line:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/publish.sh" path/to/file.html   # or .md
```

Then give the user the URL. That's it.

**Private / confidential content** — add a password so only people with the
secret can view it (HTTP Basic prompt, or `?k=<secret>` in the URL):

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/publish.sh" path/to/file.md --password "<secret>"
```

Share the link and the password separately. With a password the script uses the
hosted endpoint only — it never falls back to an unprotected public host.

> If multiple files need a single landing page, publish each and share the
> links, or stage them into one folder with an `index.html` first.

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

## How it decides where to publish (decision tree)

The script tries these in order and uses the first that works:

1. **Hosted endpoint** (`$PUBIFACT_ENDPOINT`) — a tiny `POST file → URL`
   service (Cloudflare Worker + R2). No account, instant, persistent, renders
   Markdown server-side. This is the default path.
2. **tmpfiles.org** — no account at all, emergency fallback, but the link
   expires in ~1 hour. Tell the user it's temporary.

## Configuration

- `PUBIFACT_ENDPOINT` — the hosted service URL (e.g.
  `https://pubifact.<account>.workers.dev`). Set this to enable tier 1.
  The backend is a small Cloudflare Worker + R2 bucket — see the project
  README to stand up your own (free tier).

## Notes

- Without `--password`, the page is **public active HTML** — anyone with the
  link can open it and any JS in it runs. Use `--password` for anything private.
- A password gates **reading**; the secret protects the content. (The separate
  `UPLOAD_TOKEN` on the backend gates **who can publish**, not who can read.)
- Relative asset references (`./img.png`, `./app.js`) won't resolve — inline
  assets or use absolute URLs so the artifact is self-contained.
