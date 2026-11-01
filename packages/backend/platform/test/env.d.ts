declare namespace Cloudflare {
  interface Env {
    readonly DB: D1Database;
    readonly MEDIA: R2Bucket;
    readonly ACTIVATED_ROOM: DurableObjectNamespace;
    readonly BROKEN_ROOM: DurableObjectNamespace;
  }

  interface Exports {
    readonly default: Fetcher;
  }
}

// Vite resolves this at build time.
interface ImportMeta {
  glob<T>(
    pattern: string,
    options: { readonly eager: true; readonly import: "default" },
  ): Record<string, T>;
}
