// pubifact — Cloudflare Worker
// POST /up   : accept an artifact (multipart "file"/"html" field, or raw body),
//              store it in R2 under a random slug, return the shareable URL.
//              Markdown (.md/.markdown, or ?type=md) is rendered to HTML.
// GET  /:key : serve the stored HTML with content-type text/html so it renders.
// GET  /     : tiny usage page.
//
// Design notes:
// - We host arbitrary *active* HTML (interactive explainers ship JS), so we can
//   NOT lock it down with a script-blocking CSP — that would defeat the purpose.
//   Mitigation instead: serve from the cookie-less workers.dev origin + nosniff,
//   size cap, and an OPTIONAL upload token (env.UPLOAD_TOKEN) the operator can
//   flip on if abuse appears. This matches the trust model of surge/neocities.

import { marked } from 'marked'

const SLUG_LEN = 8
// Crockford-ish alphabet: no 0/o/1/l/i ambiguity.
const ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789'
const MAX_BYTES = 5 * 1024 * 1024 // 5 MB

export default {
  async fetch(req, env) {
    const url = new URL(req.url)
    const { pathname } = url

    if (req.method === 'OPTIONS') {
      return new Response(null, { headers: cors() })
    }

    if (req.method === 'POST' && (pathname === '/up' || pathname === '/')) {
      return upload(req, env, url)
    }

    const isRead = req.method === 'GET' || req.method === 'HEAD'
    if (isRead && pathname === '/') {
      const body = req.method === 'HEAD' ? null : home(url.origin)
      return new Response(body, { headers: { 'content-type': 'text/html; charset=utf-8' } })
    }

    if (isRead) {
      return serve(req, url, env, req.method)
    }

    return text('method not allowed\n', 405)
  },
}

async function upload(req, env, url) {
  // Optional shared-secret gate. Unset => fully open (zero-setup for users).
  if (env.UPLOAD_TOKEN) {
    const auth = req.headers.get('authorization') || ''
    if (auth !== `Bearer ${env.UPLOAD_TOKEN}`) {
      return json({ error: 'unauthorized' }, 401)
    }
  }

  let body
  let filename = ''
  let password = null
  const ct = req.headers.get('content-type') || ''
  if (ct.includes('multipart/form-data')) {
    const form = await req.formData()
    const file = form.get('file') || form.get('html')
    if (!file || typeof file === 'string') {
      return json({ error: 'expected a "file" field' }, 400)
    }
    body = await file.arrayBuffer()
    filename = file.name || ''
    const pw = form.get('password')
    if (typeof pw === 'string' && pw.length > 0) password = pw
  } else {
    body = await req.arrayBuffer()
    filename = url.searchParams.get('name') || ''
    password = url.searchParams.get('pw') || null
  }

  if (body.byteLength === 0) return json({ error: 'empty body' }, 400)
  if (body.byteLength > MAX_BYTES) return json({ error: 'too large (>5MB)' }, 413)

  // Markdown → HTML so docs render as readable pages, not raw text.
  let stored = body
  const isMd = /\.(md|markdown)$/i.test(filename) || url.searchParams.get('type') === 'md'
  if (isMd) {
    const src = new TextDecoder().decode(body)
    const rendered = await marked.parse(src)
    stored = new TextEncoder().encode(mdShell(rendered, titleFrom(filename, src)))
  }

  // Optional per-link read protection: store a salted hash, enforced on GET.
  const putOpts = { httpMetadata: { contentType: 'text/html; charset=utf-8' } }
  if (password) {
    const salt = randomHex(16)
    putOpts.customMetadata = { pwsalt: salt, pwhash: await hashPw(password, salt) }
  }

  const key = `${randomSlug()}.html`
  await env.BUCKET.put(key, stored, putOpts)

  const link = `${url.origin}/${key}`
  if ((req.headers.get('accept') || '').includes('application/json')) {
    return json({ url: link }, 200)
  }
  // Plain text by default — easy to capture from curl.
  return text(`${link}\n`, 200)
}

async function serve(req, url, env, method = 'GET') {
  const key = url.pathname.slice(1)
  const obj = await env.BUCKET.get(key)
  if (!obj) return text('not found\n', 404)

  const pwhash = obj.customMetadata?.pwhash
  if (pwhash) {
    const given = providedPassword(req, url)
    const ok = given && (await hashPw(given, obj.customMetadata?.pwsalt || '')) === pwhash
    if (!ok) {
      return new Response('password required\n', {
        status: 401,
        headers: {
          ...cors(),
          'www-authenticate': 'Basic realm="pubifact"',
          'content-type': 'text/plain; charset=utf-8',
        },
      })
    }
  }

  const headers = new Headers(cors())
  headers.set('content-type', obj.httpMetadata?.contentType || 'text/html; charset=utf-8')
  headers.set('x-content-type-options', 'nosniff')
  // Protected pages must not be cached by shared caches.
  headers.set('cache-control', pwhash ? 'private, no-store' : 'public, max-age=600')
  return new Response(method === 'HEAD' ? null : obj.body, { headers })
}

// Read a candidate password from HTTP Basic auth (any username) or ?k=.
function providedPassword(req, url) {
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

function randomHex(n) {
  const b = new Uint8Array(n)
  crypto.getRandomValues(b)
  return [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
}

async function hashPw(pw, saltHex) {
  const data = new TextEncoder().encode(`${saltHex}:${pw}`)
  const digest = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('')
}

function randomSlug() {
  const b = new Uint8Array(SLUG_LEN)
  crypto.getRandomValues(b)
  let s = ''
  for (const x of b) s += ALPHABET[x % ALPHABET.length]
  return s
}

function cors() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'content-type,authorization',
  }
}

function text(s, status) {
  return new Response(s, {
    status,
    headers: { ...cors(), 'content-type': 'text/plain; charset=utf-8' },
  })
}

function json(o, status) {
  return new Response(`${JSON.stringify(o)}\n`, {
    status,
    headers: { ...cors(), 'content-type': 'application/json' },
  })
}

function titleFrom(filename, src) {
  const h1 = src.match(/^#\s+(.+)$/m)
  if (h1) return h1[1].trim()
  const base = (filename || 'document').replace(/\.(md|markdown|html?)$/i, '')
  return base || 'document'
}

function mdShell(bodyHtml, title) {
  const safe = String(title).replace(
    /[<>&]/g,
    (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;' })[c],
  )
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

function home(origin) {
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
