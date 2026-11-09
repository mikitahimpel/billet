import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";
import { defaultTestNow } from "./test/test-now.ts";

// The instant the test rooms live at; see test/test-now.ts.
const bindings = { TEST_NOW: process.env["TEST_NOW"] ?? defaultTestNow };

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
              bindings,
              d1Databases: ["DB"],
              r2Buckets: ["MEDIA"],
              kvNamespaces: ["STATUS", "TITLES"],
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
              bindings,
              durableObjects: {
                STUB_DEMO_ROOM: { className: "StubbedDemoRoom", useSQLite: true },
                HANG_DEMO_ROOM: { className: "HangingApnsRoom", useSQLite: true },
                CLOCK_DEMO_ROOM: { className: "ClockedDemoRoom", useSQLite: true },
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
          // drizzle-kit spawns here with only the default timeout, so it runs before the workerd
          // projects instead of beside them, where they starve it.
          sequence: { groupOrder: 0 },
        },
      },
    ],
  },
});
