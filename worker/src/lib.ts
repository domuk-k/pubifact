// pubifact — pure helpers (no bindings, no I/O beyond WebCrypto).
// Kept separate from index.ts so they can be unit-tested directly.

export const SLUG_LEN = 8
// Crockford-ish alphabet: no 0/o/1/l/i ambiguity.
export const ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789'
export const MAX_BYTES = 5 * 1024 * 1024 // 5 MB

// Read a candidate password from HTTP Basic auth (any username) or ?k=.
export function providedPassword(req: Request, url: URL): string | null {
  const h = req.headers.get('authorization') || ''
  if (h.startsWith('Basic ')) {
    try {
      const dec = atob(h.slice(6))
      const i = dec.indexOf(':')
      return i >= 0 ? dec.slice(i + 1) : dec
    } catch {
      /* fall through */
    }
  }
  return url.searchParams.get('k')
}

export function randomHex(n: number): string {
  const b = new Uint8Array(n)
  crypto.getRandomValues(b)
  return [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
}

// Salted SHA-256, deliberately NOT a slow KDF: the hash lives in R2
// customMetadata next to the very object it gates — anyone who can read the
// metadata can read the content, so offline-cracking resistance buys nothing.
// A slow KDF would also blow the Workers free-tier CPU budget on every GET.
// This is a share-secret for a link, not an account credential.
export async function hashPw(pw: string, saltHex: string): Promise<string> {
  const data = new TextEncoder().encode(`${saltHex}:${pw}`)
  const digest = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('')
}

export function randomSlug(): string {
  const b = new Uint8Array(SLUG_LEN)
  crypto.getRandomValues(b)
  let s = ''
  for (const x of b) s += ALPHABET[x % ALPHABET.length]
  return s
}

export function cors(): Record<string, string> {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,DELETE,OPTIONS',
    'access-control-allow-headers': 'content-type,authorization',
  }
}

export function text(s: string, status: number): Response {
  return new Response(s, {
    status,
    headers: { ...cors(), 'content-type': 'text/plain; charset=utf-8' },
  })
}

export function json(o: unknown, status: number): Response {
  return new Response(`${JSON.stringify(o)}\n`, {
    status,
    headers: { ...cors(), 'content-type': 'application/json' },
  })
}

export function titleFrom(filename: string, src: string): string {
  const h1 = src.match(/^#\s+(.+)$/m)
  if (h1?.[1]) return h1[1].trim()
  const base = (filename || 'document').replace(/\.(md|markdown|html?)$/i, '')
  return base || 'document'
}

const TITLE_ESCAPES: Record<string, string> = { '<': '&lt;', '>': '&gt;', '&': '&amp;' }

export function mdShell(bodyHtml: string, title: string): string {
  const safe = String(title).replace(/[<>&]/g, (c) => TITLE_ESCAPES[c] ?? c)
  return `<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${safe}</title>
<style>
:root{color-scheme:light dark}
body{font:16px/1.7 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;max-width:760px;margin:3rem auto;padding:0 1.3rem;color:#1a1a1a}
@media(prefers-color-scheme:dark){body{background:#0d1117;color:#c9d1d9}a{color:#58a6ff}code,pre{background:#161b22 !important}th,td{border-color:#30363d !important}}
h1,h2,h3,h4{line-height:1.3;margin:1.8em 0 .6em;font-weight:650}
h1{font-size:1.9rem;margin-top:0}h2{font-size:1.45rem;border-bottom:1px solid #eaecef;padding-bottom:.3em}
a{color:#0b5fff;text-decoration:none}a:hover{text-decoration:underline}
code{background:#f4f4f5;padding:.15em .4em;border-radius:5px;font-size:.9em}
pre{background:#f4f4f5;padding:1rem;border-radius:8px;overflow:auto}pre code{background:none;padding:0}
blockquote{margin:1em 0;padding:.2em 1em;border-left:4px solid #d0d7de;color:#57606a}
table{border-collapse:collapse;width:100%;margin:1em 0}th,td{border:1px solid #d0d7de;padding:.5em .8em;text-align:left}
img{max-width:100%}hr{border:0;border-top:1px solid #eaecef;margin:2em 0}
</style>
<article>${bodyHtml}</article>`
}

export function home(origin: string): string {
  return `<!doctype html><meta charset="utf-8"><title>pubifact</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:680px;margin:4rem auto;padding:0 1.2rem}code{background:#f4f4f5;padding:.15em .4em;border-radius:4px}pre{background:#f4f4f5;padding:1rem;border-radius:8px;overflow:auto}</style>
<h1>pubifact</h1>
<p>POST an HTML or Markdown file, get a shareable URL back.</p>
<pre>curl -F file=@page.html ${origin}/up
curl -F file=@notes.md  ${origin}/up

# private — require a password to view:
curl -F file=@notes.md -F password=secret ${origin}/up</pre>
<p>The response is the URL of your rendered page. No account needed.
Protected pages prompt for the password (or append <code>?k=secret</code>).</p>`
}
