/// <reference types="@cloudflare/vitest-pool-workers/types" />

// `env` from 'cloudflare:test' is typed as `Cloudflare.Env`. This worker runs
// `wrangler types --include-env=false`, so `Cloudflare.Env` isn't generated from
// bindings — augment it here to mirror the worker's own Env (src/index.ts).
declare namespace Cloudflare {
  interface Env {
    BUCKET: R2Bucket
    UPLOAD_TOKEN?: string
  }
}

declare module 'cloudflare:test' {
  interface ProvidedEnv {
    BUCKET: R2Bucket
    UPLOAD_TOKEN?: string
  }
}
