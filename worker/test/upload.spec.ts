import { SELF } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'

describe('upload — POST /up', () => {
  it('multipart HTML upload → 200 + URL body matching slug pattern', async () => {
    const form = new FormData()
    form.append('file', new File(['<h1>hello</h1>'], 'page.html', { type: 'text/html' }))

    const res = await SELF.fetch('https://example.com/up', { method: 'POST', body: form })
    expect(res.status).toBe(200)

    // Two lines: line 1 = URL, line 2 = delete token (16-byte hex).
    const body = await res.text()
    expect(body).toMatch(/^https:\/\/.+\/[a-z2-9]{8}\.html\n[0-9a-f]{32}\n$/)
  })

  it('markdown file upload → fetching the URL renders <em> and <title>', async () => {
    const mdContent = '# My Doc\n\nHello *world*'
    const form = new FormData()
    form.append('file', new File([mdContent], 'notes.md', { type: 'text/markdown' }))

    const uploadRes = await SELF.fetch('https://example.com/up', { method: 'POST', body: form })
    expect(uploadRes.status).toBe(200)
    const [url = ''] = (await uploadRes.text()).split('\n')

    const serveRes = await SELF.fetch(url)
    expect(serveRes.status).toBe(200)
    const html = await serveRes.text()
    expect(html).toContain('<em>')
    expect(html).toContain('<title>My Doc</title>')
  })

  it('raw body with ?type=md&name=x.md renders markdown', async () => {
    const mdContent = '# Raw\n\nSome *text*'
    const res = await SELF.fetch('https://example.com/up?type=md&name=x.md', {
      method: 'POST',
      headers: { 'content-type': 'text/plain' },
      body: mdContent,
    })
    expect(res.status).toBe(200)
    const [url = ''] = (await res.text()).split('\n')

    const serveRes = await SELF.fetch(url)
    const html = await serveRes.text()
    expect(html).toContain('<em>')
    expect(html).toContain('<title>Raw</title>')
  })

  it('empty body → 400', async () => {
    const res = await SELF.fetch('https://example.com/up', {
      method: 'POST',
      headers: { 'content-type': 'text/plain' },
      body: '',
    })
    expect(res.status).toBe(400)
  })

  it('body > 5MB → 413', async () => {
    const big = new Uint8Array(5 * 1024 * 1024 + 1)
    const res = await SELF.fetch('https://example.com/up', {
      method: 'POST',
      headers: { 'content-type': 'application/octet-stream' },
      body: big,
    })
    expect(res.status).toBe(413)
  })

  it('Accept: application/json → {url}', async () => {
    const form = new FormData()
    form.append('file', new File(['<p>hi</p>'], 'hi.html', { type: 'text/html' }))

    const res = await SELF.fetch('https://example.com/up', {
      method: 'POST',
      headers: { accept: 'application/json' },
      body: form,
    })
    expect(res.status).toBe(200)
    const json = await res.json<{ url: string }>()
    expect(json).toHaveProperty('url')
    expect(json.url).toMatch(/^https:\/\/.+\/[a-z2-9]{8}\.html$/)
  })
})
