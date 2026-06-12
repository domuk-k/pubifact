import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { describe, expect, it } from 'vitest'
import worker from '../src/index'

function makeUploadRequest(headers: Record<string, string> = {}): Request {
  const form = new FormData()
  form.append('file', new File(['<p>test</p>'], 'test.html', { type: 'text/html' }))
  return new Request('https://example.com/up', { method: 'POST', body: form, headers })
}

describe('auth — UPLOAD_TOKEN gate', () => {
  it('no bearer when UPLOAD_TOKEN set → 401', async () => {
    const ctx = createExecutionContext()
    const testEnv = { ...env, UPLOAD_TOKEN: 'sekrit' }
    const res = await worker.fetch(makeUploadRequest(), testEnv, ctx)
    await waitOnExecutionContext(ctx)
    expect(res.status).toBe(401)
  })

  it('correct bearer when UPLOAD_TOKEN set → 200', async () => {
    const ctx = createExecutionContext()
    const testEnv = { ...env, UPLOAD_TOKEN: 'sekrit' }
    const res = await worker.fetch(
      makeUploadRequest({ authorization: 'Bearer sekrit' }),
      testEnv,
      ctx,
    )
    await waitOnExecutionContext(ctx)
    expect(res.status).toBe(200)
  })

  it('wrong bearer → 401', async () => {
    const ctx = createExecutionContext()
    const testEnv = { ...env, UPLOAD_TOKEN: 'sekrit' }
    const res = await worker.fetch(
      makeUploadRequest({ authorization: 'Bearer wrongtoken' }),
      testEnv,
      ctx,
    )
    await waitOnExecutionContext(ctx)
    expect(res.status).toBe(401)
  })

  it('without UPLOAD_TOKEN set → open (200 without auth)', async () => {
    const ctx = createExecutionContext()
    // env from cloudflare:test has BUCKET but no UPLOAD_TOKEN by default
    const testEnv = { ...env, UPLOAD_TOKEN: undefined }
    const res = await worker.fetch(makeUploadRequest(), testEnv, ctx)
    await waitOnExecutionContext(ctx)
    expect(res.status).toBe(200)
  })
})
