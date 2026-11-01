import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

// Everything here runs inside workerd, with the `PairRoom` binding from alchemy.run.ts. The date
// is the newest this pool's workerd supports; Alchemy deploys with its own default.
export default defineConfig({
  plugins: [
    cloudflareTest({
      main: "./test/test-worker.ts",
      miniflare: {
        compatibilityDate: "2026-08-15",
        compatibilityFlags: ["nodejs_compat"],
        durableObjects: {
          PAIR_ROOM: { className: "PairRoom", useSQLite: true },
        },
      },
    }),
  ],
});
