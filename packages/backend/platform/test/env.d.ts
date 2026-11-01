declare namespace Cloudflare {
  interface Env {
    readonly DB: D1Database;
    readonly ACTIVATED_ROOM: DurableObjectNamespace;
    readonly BROKEN_ROOM: DurableObjectNamespace;
  }
}

// Vite resolves this at build time.
interface ImportMeta {
  glob<T>(
    pattern: string,
    options: { readonly eager: true; readonly import: "default" },
  ): Record<string, T>;
}
