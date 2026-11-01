declare namespace Cloudflare {
  interface Env {
    readonly DB: D1Database;
    readonly STUB_DEMO_ROOM: DurableObjectNamespace<
      import("../src/demo-room-durable-object.ts").DemoRoom
    >;
    readonly DEMO_ROOM: DurableObjectNamespace<
      import("../src/demo-room-durable-object.ts").DemoRoom
    >;
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
