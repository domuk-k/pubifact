import { SELF } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'

/** Upload a file and return the key (path segment after origin) */
async function uploadFile(content: string, name: string, password?: string): Promise<string> {
  const form = new FormData()
  form.append('file', new File([content], name, { type: 'text/html' }))
  if (password) form.append('password', password)

  const res = await SELF.fetch('https://example.com/up', { method: 'POST', body: form })
  const url = (await res.text()).trim()
  // Return full URL
  return url
}

describe('serve — GET /:key', () => {
  it('unknown key → 404', async () => {
    const res = await SELF.fetch('https://example.com/aaaaaaaa.html')
    expect(res.status).toBe(404)
  })

  it('public page → 200 + cache-control public, max-age=600', async () => {
    const url = await uploadFile('<p>public</p>', 'pub.html')
    const res = await SELF.fetch(url)
    expect(res.status).toBe(200)
    expect(res.headers.get('cache-control')).toBe('public, max-age=600')
  })

  it('HEAD → headers present, empty body', async () => {
    const url = await uploadFile('<p>head test</p>', 'head.html')
    const res = await SELF.fetch(url, { method: 'HEAD' })
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toContain('text/html')
    const body = await res.text()
    expect(body).toBe('')
  })

  describe('password-protected page', () => {
    it('no auth → 401 + www-authenticate Basic', async () => {
      const url = await uploadFile('<p>secret</p>', 'secret.html', 'mypass')
      const res = await SELF.fetch(url)
      expect(res.status).toBe(401)
      const wwwAuth = res.headers.get('www-authenticate') || ''
      expect(wwwAuth.toLowerCase()).toContain('basic')
    })

    it('Basic correct password → 200 + cache-control private, no-store', async () => {
      const url = await uploadFile('<p>secret</p>', 'secret2.html', 'mypass')
      const auth = btoa('user:mypass')
      const res = await SELF.fetch(url, {
        headers: { authorization: `Basic ${auth}` },
      })
      expect(res.status).toBe(200)
      expect(res.headers.get('cache-control')).toBe('private, no-store')
    })

    it('?k=correct → 200', async () => {
      const url = await uploadFile('<p>secret</p>', 'secret3.html', 'mypass')
      const res = await SELF.fetch(`${url}?k=mypass`)
      expect(res.status).toBe(200)
    })

    it('?k=wrong → 401', async () => {
      const url = await uploadFile('<p>secret</p>', 'secret4.html', 'mypass')
      const res = await SELF.fetch(`${url}?k=wrongpass`)
      expect(res.status).toBe(401)
    })
  })
})

describe('serve — GET /', () => {
  it('GET / → 200 usage page', async () => {
    const res = await SELF.fetch('https://example.com/')
    expect(res.status).toBe(200)
    const html = await res.text()
    expect(html).toContain('pubifact')
  })
})
