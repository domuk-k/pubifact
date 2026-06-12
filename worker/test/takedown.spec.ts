import { createExecutionContext, env, SELF, waitOnExecutionContext } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'
import worker from '../src/index'

/** Publish a file and return { url, token } from the two-line text response. */
async function publish(
  content: string,
  name = 'page.html',
): Promise<{ url: string; token: string }> {
  const form = new FormData()
  form.append('file', new File([content], name, { type: 'text/html' }))
  const res = await SELF.fetch('https://example.com/up', { method: 'POST', body: form })
  const [url = '', token = ''] = (await res.text()).split('\n')
  return { url, token }
}

describe('takedown — DELETE /:key', () => {
  it('full lifecycle: publish → GET 200 → DELETE 200 → GET 404', async () => {
    const { url, token } = await publish('<p>bye</p>')

    const get1 = await SELF.fetch(url)
    expect(get1.status).toBe(200)

    const del = await SELF.fetch(url, {
      method: 'DELETE',
      headers: { authorization: `Bearer ${token}` },
    })
    expect(del.status).toBe(200)
    expect(await del.text()).toBe('deleted\n')

    const get2 = await SELF.fetch(url)
    expect(get2.status).toBe(404)
  })

  it('wrong token → 401, page stays up', async () => {
    const { url } = await publish('<p>stay</p>')
    const del = await SELF.fetch(url, {
      method: 'DELETE',
      headers: { authorization: 'Bearer not-the-right-token' },
    })
    expect(del.status).toBe(401)
    const get = await SELF.fetch(url)
    expect(get.status).toBe(200)
  })

  it('no token → 401', async () => {
    const { url } = await publish('<p>noauth</p>')
    const del = await SELF.fetch(url, { method: 'DELETE' })
    expect(del.status).toBe(401)
  })

  it('unknown key → 404', async () => {
    const res = await SELF.fetch('https://example.com/zzzzzzzz.html', {
      method: 'DELETE',
      headers: { authorization: 'Bearer whatever' },
    })
    expect(res.status).toBe(404)
  })

  it('Accept: application/json → { deleted: key }', async () => {
    const { url, token } = await publish('<p>json</p>')
    const key = new URL(url).pathname.slice(1)
    const del = await SELF.fetch(url, {
      method: 'DELETE',
      headers: { authorization: `Bearer ${token}`, accept: 'application/json' },
    })
    expect(del.status).toBe(200)
    expect(await del.json()).toEqual({ deleted: key })
  })

  it('operator override: UPLOAD_TOKEN deletes an artifact regardless of its own token', async () => {
    // Publish openly via SELF (no UPLOAD_TOKEN in that env), then delete using
    // the operator key by invoking the handler directly with UPLOAD_TOKEN set.
    const { url } = await publish('<p>operator</p>')

    const ctx = createExecutionContext()
    const testEnv = { ...env, UPLOAD_TOKEN: 'master-key' }
    const del = await worker.fetch(
      new Request(url, { method: 'DELETE', headers: { authorization: 'Bearer master-key' } }),
      testEnv,
      ctx,
    )
    await waitOnExecutionContext(ctx)
    expect(del.status).toBe(200)
  })

  it('CORS preflight advertises DELETE', async () => {
    const res = await SELF.fetch('https://example.com/x.html', { method: 'OPTIONS' })
    expect(res.headers.get('access-control-allow-methods')).toContain('DELETE')
  })
})
