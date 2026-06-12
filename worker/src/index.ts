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
import {
  cors,
  hashPw,
  home,
  json,
  MAX_BYTES,
  mdShell,
  providedPassword,
  randomHex,
  randomSlug,
  text,
  titleFrom,
} from './lib'

interface Env {
  BUCKET: R2Bucket
  /** Optional bearer-token gate on POST /up. Unset = fully open instance. */
  UPLOAD_TOKEN?: string
}

export default {
  async fetch(req, env, _ctx) {
    const url = new URL(req.url)
    const { pathname } = url

    if (req.method === 'OPTIONS') {
      return new Response(null, { headers: cors() })
    }

    if (req.method === 'POST' && (pathname === '/up' || pathname === '/')) {
      return upload(req, env, url)
    }

    if (req.method === 'DELETE') return remove(req, env, url)

    const isRead = req.method === 'GET' || req.method === 'HEAD'
    if (isRead && pathname === '/') {
      const body = req.method === 'HEAD' ? null : home(url.origin)
      return new Response(body, { headers: { 'content-type': 'text/html; charset=utf-8' } })
    }

    if (isRead) {
      return serve(req, url, env, req.method as 'GET' | 'HEAD')
    }

    return text('method not allowed\n', 405)
  },
} satisfies ExportedHandler<Env>

async function upload(req: Request, env: Env, url: URL): Promise<Response> {
  // Optional shared-secret gate. Unset => fully open (zero-setup for users).
  if (env.UPLOAD_TOKEN) {
    const auth = req.headers.get('authorization') || ''
    if (auth !== `Bearer ${env.UPLOAD_TOKEN}`) {
      return json({ error: 'unauthorized' }, 401)
    }
  }

  let body: ArrayBuffer
  let filename = ''
  let password: string | null = null
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
  let stored: ArrayBuffer | Uint8Array = body
  const isMd = /\.(md|markdown)$/i.test(filename) || url.searchParams.get('type') === 'md'
  if (isMd) {
    const src = new TextDecoder().decode(body)
    const rendered = await marked.parse(src)
    stored = new TextEncoder().encode(mdShell(rendered, titleFrom(filename, src)))
  }

  // customMetadata carries two independent, salted-hash keypairs:
  //   pwsalt/pwhash  — optional read protection (who can VIEW the page)
  //   delsalt/delhash — always set; gates takedown (who can DELETE the page)
  const meta: Record<string, string> = {}

  // Optional per-link read protection: store a salted hash, enforced on GET.
  if (password) {
    const salt = randomHex(16)
    meta.pwsalt = salt
    meta.pwhash = await hashPw(password, salt)
  }

  // Per-artifact takedown token: minted on every upload, returned once.
  const deleteToken = randomHex(16)
  const delsalt = randomHex(16)
  meta.delsalt = delsalt
  meta.delhash = await hashPw(deleteToken, delsalt)

  const putOpts: R2PutOptions = {
    httpMetadata: { contentType: 'text/html; charset=utf-8' },
    customMetadata: meta,
  }

  const key = `${randomSlug()}.html`
  await env.BUCKET.put(key, stored, putOpts)

  const link = `${url.origin}/${key}`
  if ((req.headers.get('accept') || '').includes('application/json')) {
    return json({ url: link, deleteToken }, 200)
  }
  // Plain text by default — line 1 = URL (capture this), line 2 = delete token.
  return text(`${link}\n${deleteToken}\n`, 200)
}

async function remove(req: Request, env: Env, url: URL): Promise<Response> {
  const key = url.pathname.slice(1)
  // Metadata only — no body fetch; we just need the delete-hash to authorize.
  const obj = await env.BUCKET.head(key)
  if (!obj) return text('not found\n', 404)

  const auth = req.headers.get('authorization') || ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : ''

  // Two ways to take down: the operator's master key, or the per-artifact token.
  const operator = !!(env.UPLOAD_TOKEN && token === env.UPLOAD_TOKEN)
  const delhash = obj.customMetadata?.delhash
  const delsalt = obj.customMetadata?.delsalt || ''
  const owner = !!(delhash && token && (await hashPw(token, delsalt)) === delhash)
  if (!operator && !owner) return json({ error: 'unauthorized' }, 401)

  await env.BUCKET.delete(key)

  // Evict the edge cache so a public takedown is immediate. Defensive: the
  // delete already succeeded, so a cache miss/throw here must not fail the call.
  try {
    await caches.default.delete(`${url.origin}/${key}`)
  } catch {
    /* edge cache may be unavailable (e.g. in tests) — ignore */
  }

  if ((req.headers.get('accept') || '').includes('application/json')) {
    return json({ deleted: key }, 200)
  }
  return text('deleted\n', 200)
}

async function serve(req: Request, url: URL, env: Env, method: 'GET' | 'HEAD'): Promise<Response> {
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
