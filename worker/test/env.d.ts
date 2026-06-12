declare module 'cloudflare:test' {
  interface ProvidedEnv {
    BUCKET: R2Bucket
    UPLOAD_TOKEN?: string
  }
}
