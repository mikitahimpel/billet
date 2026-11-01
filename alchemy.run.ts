// Infrastructure for billet, declared with Alchemy v2 (beta). See docs/alchemy.md.
//
// Nothing personal lives here: physical names derive from the stack, the stage (`--stage` or
// ALCHEMY_STAGE) and the logical ids below. The Cloudflare account comes from CLOUDFLARE_ACCOUNT_ID
// and CLOUDFLARE_API_TOKEN, read only by a real deploy. `alchemy dev` emulates every resource here
// locally and needs no credentials.
import * as Cloudflare from "@alchemy.run/cloudflare";
import { providers as drizzleProviders } from "@alchemy.run/drizzle/Providers";
import { Schema } from "@alchemy.run/drizzle/Schema";
import * as Alchemy from "alchemy";
import * as State from "alchemy/State";
import * as Effect from "effect/Effect";
import * as FileSystem from "effect/FileSystem";
import * as HttpClient from "effect/http/HttpClient";
import * as Layer from "effect/Layer";
import * as Path from "effect/Path";
import * as D1State from "./alchemy-d1-state.ts";

// The tables of the cross-couple directory. A deploy applies the committed migrations.
// `pnpm db:generate` writes them, and a test fails if a schema change has none.
// Import the subpaths above, not the package root: that pulls `@effect/sql-d1`, which needs effect
// 4.1, into this effect 4.0 process.
export const DirectorySchema = Schema("DirectorySchema", {
  schema: "./packages/backend/platform/src/directory-schema.ts",
  out: "./packages/backend/platform/migrations/directory",
  dialect: "sqlite",
});

// The cross-couple directory.
export const Database = Effect.gen(function* () {
  const migrations = yield* DirectorySchema;
  return yield* Cloudflare.D1.Database("Database", { migrations });
});

// Note images. Private: no public access and no custom domain, so every read goes through the
// Worker and its authorisation checks.
export const Media = Cloudflare.R2.Bucket("Media");

// A deployed stage (`dev` or `prod`) keeps its state in D1, so it survives CI runners and
// checkouts. `alchemy dev` keeps it in the gitignored `.alchemy/` folder.
const state = Layer.unwrap(
  Effect.gen(function* () {
    const local = yield* Alchemy.ALCHEMY_DEV;
    return local
      ? State.localState()
      : (D1State.d1State({ databaseName: "billet-alchemy-state" }) as Layer.Layer<
          State.State,
          never,
          HttpClient.HttpClient | FileSystem.FileSystem | Path.Path
        >);
  }).pipe(Effect.orDie),
);

export default Alchemy.Stack(
  "billet",
  {
    providers: Layer.mergeAll(Cloudflare.providers(), drizzleProviders()),
    state,
  },
  Effect.gen(function* () {
    const db = yield* Database;
    const media = yield* Media;

    // Bindings must match packages/backend/platform/src/worker-env.ts. `PairRoom` is the class
    // exported by apps/api/src/worker.ts, one object per couple, SQLite-backed by default.
    const api = yield* Cloudflare.Worker("Api", {
      main: "./apps/api/src/worker.ts",
      env: {
        DB: db,
        MEDIA: media,
        PAIR_ROOM: Cloudflare.DurableObject("PairRoom"),
      },
      dev: { host: "0.0.0.0", port: 8787 },
    });

    return { url: api.url };
  }),
);
