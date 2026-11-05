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
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as FileSystem from "effect/FileSystem";
import * as HttpClient from "effect/http/HttpClient";
import * as Layer from "effect/Layer";
import * as Option from "effect/Option";
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

// The service status (maintenance, minimum build, notice), apart from D1 so it can be switched on
// and served while the database is down. The admin panel writes it (docs/maintenance.md).
export const Status = Cloudflare.KV.Namespace("Status");

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
    const stage = yield* Alchemy.Stage;
    const db = yield* Database;
    const media = yield* Media;
    const status = yield* Status;
    // A token that can only read Account Analytics, for the admin's trends (docs/admin.md). Bound
    // only when the deploy has it (.env.pass.analytics-read); without it the trends use D1 alone.
    const analyticsReadToken = yield* Config.option(Config.Redacted("ANALYTICS_READ_TOKEN"));
    // Accepted app events, written by the Worker (docs/experiments.md). Analytics Engine makes a
    // dataset on its first write, so a deploy creates nothing else. One dataset per stage.
    const events = yield* Cloudflare.AnalyticsEngine.Dataset("Events", {
      dataset: `billet_${stage}_events`,
    });

    // Workers Logs and traces (docs/observability.md). Head sampling keeps or drops a whole
    // request, its log lines and its trace together. Dev keeps every request; prod is planned at
    // 15% and can be changed for one deploy with API_SAMPLING_RATE (0 to 1).
    const samplingRate = yield* Config.Number("API_SAMPLING_RATE").pipe(
      Config.withDefault(stage === "dev" ? 1 : 0.15),
    );
    const observability = {
      enabled: true,
      headSamplingRate: samplingRate,
      // Query strings can hold something personal; the Worker's own lines never carry them.
      redactQueryString: true,
      logs: { enabled: true, invocationLogs: true, headSamplingRate: samplingRate, persist: true },
      traces: { enabled: true, headSamplingRate: samplingRate, persist: true },
    };

    // Bindings must match packages/backend/platform/src/worker-env.ts. `PairRoom` is the class
    // exported by apps/api/src/worker.ts, one object per couple, SQLite-backed by default.
    const api = yield* Cloudflare.Worker("Api", {
      main: "./apps/api/src/worker.ts",
      env: {
        DB: db,
        MEDIA: media,
        STATUS: status,
        EVENTS: events,
        // Shown in the admin panel's top bar, so the owner always sees which stage they change.
        // Payments read it too: only `dev` takes Xcode and mock purchases (docs/payments.md).
        STAGE: stage,
        // The Cloudflare Access application in front of /admin (docs/admin.md). Not secret, but
        // kept out of the public repo: they come from the deploy's environment. Empty keeps the
        // panel closed to everyone.
        ACCESS_TEAM_DOMAIN: Config.String("ACCESS_TEAM_DOMAIN").pipe(Config.withDefault("")),
        ACCESS_AUD: Config.String("ACCESS_AUD").pipe(Config.withDefault("")),
        // The Access application that lets agents' service tokens read /admin/api/agent. Empty
        // keeps the agent routes closed.
        ACCESS_AGENT_AUD: Config.String("ACCESS_AGENT_AUD").pipe(Config.withDefault("")),
        ...(Option.isSome(analyticsReadToken)
          ? {
              ANALYTICS_READ_TOKEN: analyticsReadToken.value,
              ANALYTICS_ACCOUNT_ID: Config.String("CLOUDFLARE_ACCOUNT_ID"),
            }
          : {}),
        PAIR_ROOM: Cloudflare.DurableObject("PairRoom"),
        // Temporary demo rooms: bound on the dev stage only, so no other stage serves /demo.
        // The Sign in with Apple key revokes a deleted account's Apple token. Only the dev vault
        // has it so far; prod needs it in "Billet Release" first (docs/alchemy.md).
        ...(stage === "dev"
          ? {
              DEMO_ROOM: Cloudflare.DurableObject("DemoRoom"),
              APNS_KEY: Config.Redacted("APNS_KEY"),
              APNS_KEY_ID: Config.Redacted("APNS_KEY_ID"),
              APPLE_SIGN_IN_KEY: Config.Redacted("APPLE_SIGN_IN_KEY"),
              APPLE_SIGN_IN_KEY_ID: Config.Redacted("APPLE_SIGN_IN_KEY_ID"),
            }
          : {}),
      },
      observability,
      dev: { host: "0.0.0.0", port: 8787 },
    });

    return { url: api.url };
  }),
);
