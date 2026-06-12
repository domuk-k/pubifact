/// <reference types="@cloudflare/vitest-pool-workers/types" />

declare module 'cloudflare:test' {
  interface ProvidedEnv {
    BUCKET: R2Bucket
    UPLOAD_TOKEN?: string
  }
}
