import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

// `*.node.test.ts` runs drizzle-kit, which needs Node. Everything else runs inside workerd, with the
// bindings from alchemy.run.ts. The date is the newest this pool's workerd supports; Alchemy deploys
// with its own default.
export default defineConfig({
  test: {
    projects: [
      {
        extends: true,
        plugins: [
          // Alchemy's bundler imports `.sql` as text, and migrations.js relies on it.
          {
            name: "sql-as-text",
            enforce: "pre",
            transform: (code, id) =>
              id.endsWith(".sql")
                ? { code: `export default ${JSON.stringify(code)};`, map: null }
                : undefined,
          },
          cloudflareTest({
            main: "./test/test-worker.ts",
            miniflare: {
              compatibilityDate: "2026-08-15",
              compatibilityFlags: ["nodejs_compat"],
              d1Databases: ["DB"],
              r2Buckets: ["MEDIA"],
              durableObjects: {
                PAIR_ROOM: { className: "PairRoom", useSQLite: true },
                ACTIVATED_ROOM: { className: "ActivatedRoom", useSQLite: true },
                LANE_ROOM: { className: "LaneRoom", useSQLite: true },
                LEGACY_ROOM: { className: "LegacyRoom", useSQLite: true },
                BROKEN_ROOM: { className: "BrokenRoom", useSQLite: true },
              },
            },
          }),
        ],
        test: {
          name: "workerd",
          sequence: { groupOrder: 1 },
          include: ["test/**/*.test.ts"],
          exclude: ["test/**/*.node.test.ts", "test/demo-*.test.ts"],
        },
      },
      {
        extends: true,
        plugins: [
          cloudflareTest({
            main: "./test/demo-worker.ts",
            miniflare: {
              compatibilityDate: "2026-08-15",
              compatibilityFlags: ["nodejs_compat"],
              durableObjects: {
                STUB_DEMO_ROOM: { className: "StubbedDemoRoom", useSQLite: true },
                HANG_DEMO_ROOM: { className: "HangingApnsRoom", useSQLite: true },
                DEMO_ROOM: { className: "DemoRoom", useSQLite: true },
              },
            },
          }),
        ],
        test: {
          name: "workerd-demo",
          sequence: { groupOrder: 1 },
          include: ["test/demo-*.test.ts"],
          exclude: ["test/**/*.node.test.ts"],
        },
      },
      {
        test: {
          name: "node",
          environment: "node",
          include: ["test/**/*.node.test.ts"],
          // drizzle-kit spawns here and has only the default timeout, so it runs before the
          // workerd projects instead of beside them. Three projects at once starved it on CI.
          sequence: { groupOrder: 0 },
        },
      },
    ],
  },
});
