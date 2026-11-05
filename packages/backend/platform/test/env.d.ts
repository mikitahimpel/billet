declare namespace Cloudflare {
  interface Env {
    readonly DB: D1Database;
    /** The instant the test rooms live at, as ISO; see test-now.ts. */
    readonly TEST_NOW: string;
    readonly STUB_DEMO_ROOM: DurableObjectNamespace<
      import("../src/demo-room-durable-object.ts").DemoRoom
    >;
    readonly HANG_DEMO_ROOM: DurableObjectNamespace<
      import("../src/demo-room-durable-object.ts").DemoRoom
    >;
    readonly DEMO_ROOM: DurableObjectNamespace<
      import("../src/demo-room-durable-object.ts").DemoRoom
    >;
    readonly MEDIA: R2Bucket;
    readonly STATUS: KVNamespace;
    readonly PAIR_ROOM: DurableObjectNamespace<
      import("../src/pair-room-durable-object.ts").PairRoom
    >;
    readonly ACTIVATED_ROOM: DurableObjectNamespace;
    readonly BROKEN_ROOM: DurableObjectNamespace;
    readonly LEGACY_ROOM: DurableObjectNamespace;
    readonly LANE_ROOM: DurableObjectNamespace<
      import("../src/pair-room-durable-object.ts").PairRoom
    >;
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
