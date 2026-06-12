import { describe, expect, it } from 'vitest'
import {
  ALPHABET,
  hashPw,
  mdShell,
  providedPassword,
  randomSlug,
  SLUG_LEN,
  titleFrom,
} from '../src/lib'

describe('randomSlug', () => {
  it('returns a string of exactly SLUG_LEN characters', () => {
    const slug = randomSlug()
    expect(slug).toHaveLength(SLUG_LEN)
  })

  it('only contains characters from ALPHABET', () => {
    for (let i = 0; i < 50; i++) {
      const slug = randomSlug()
      for (const ch of slug) {
        expect(ALPHABET).toContain(ch)
      }
    }
  })
})

describe('hashPw', () => {
  it('returns a 64-character hex string', async () => {
    const h = await hashPw('password', 'salt')
    expect(h).toHaveLength(64)
    expect(h).toMatch(/^[0-9a-f]+$/)
  })

  it('is deterministic for the same password and salt', async () => {
    const h1 = await hashPw('abc', 'saltsalt')
    const h2 = await hashPw('abc', 'saltsalt')
    expect(h1).toBe(h2)
  })

  it('produces different hashes for different salts', async () => {
    const h1 = await hashPw('abc', 'salt1')
    const h2 = await hashPw('abc', 'salt2')
    expect(h1).not.toBe(h2)
  })
})

describe('titleFrom', () => {
  it('prefers a # H1 heading over the filename', () => {
    const title = titleFrom('notes.md', '# My Title\n\nsome content')
    expect(title).toBe('My Title')
  })

  it('falls back to the filename without extension when no h1', () => {
    const title = titleFrom('my-doc.md', 'just content')
    expect(title).toBe('my-doc')
  })

  it('strips .markdown extension too', () => {
    const title = titleFrom('readme.markdown', 'no heading here')
    expect(title).toBe('readme')
  })

  it('returns "document" when filename is empty and no h1', () => {
    const title = titleFrom('', '')
    expect(title).toBe('document')
  })

  it('returns "document" when result would be empty after stripping extension', () => {
    const title = titleFrom('.md', '')
    expect(title).toBe('document')
  })
})

describe('mdShell', () => {
  it('escapes < > & in the title', () => {
    const html = mdShell('<body>', '<script>alert(1)</script>')
    expect(html).toContain('&lt;script&gt;alert(1)&lt;/script&gt;')
    expect(html).not.toContain('<script>')
  })

  it('escapes & in the title', () => {
    const html = mdShell('content', 'A & B')
    expect(html).toContain('A &amp; B')
  })

  it('does not escape the body HTML', () => {
    const html = mdShell('<p>hello</p>', 'title')
    expect(html).toContain('<p>hello</p>')
  })
})

describe('providedPassword', () => {
  it('extracts password from Basic auth (username:password)', () => {
    const auth = btoa('user:mypassword')
    const req = new Request('https://example.com/', {
      headers: { authorization: `Basic ${auth}` },
    })
    const url = new URL(req.url)
    expect(providedPassword(req, url)).toBe('mypassword')
  })

  it('handles colons in password (u:a:b → password is a:b)', () => {
    const auth = btoa('u:a:b')
    const req = new Request('https://example.com/', {
      headers: { authorization: `Basic ${auth}` },
    })
    const url = new URL(req.url)
    expect(providedPassword(req, url)).toBe('a:b')
  })

  it('falls through to ?k= param when base64 decoding fails', () => {
    const req = new Request('https://example.com/?k=fallback', {
      headers: { authorization: 'Basic !!invalid!!' },
    })
    const url = new URL(req.url)
    expect(providedPassword(req, url)).toBe('fallback')
  })

  it('reads from ?k= when no Authorization header', () => {
    const req = new Request('https://example.com/?k=secret')
    const url = new URL(req.url)
    expect(providedPassword(req, url)).toBe('secret')
  })

  it('returns null when neither header nor param is present', () => {
    const req = new Request('https://example.com/')
    const url = new URL(req.url)
    expect(providedPassword(req, url)).toBeNull()
  })
})
