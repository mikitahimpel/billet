import * as D1Client from "@effect/sql-d1/D1Client";
import { makeWithDefaults } from "drizzle-orm/effect-d1";
import { Effect, Layer } from "effect";

/**
 * Drizzle over the D1 directory. Pure Effect drivers only: this must not import `alchemy` or
 * `@alchemy.run/*` (see docs/alchemy.md). The client lives in the caller's `Scope`, so open it once
 * per request.
 */
export const openDirectoryDatabase = (db: D1Database) =>
  Effect.gen(function* () {
    const services = yield* Layer.build(D1Client.layer({ db }));
    return yield* makeWithDefaults({}).pipe(Effect.provideContext(services));
  }).pipe(Effect.orDie);

export type DirectoryDatabase = Effect.Success<ReturnType<typeof openDirectoryDatabase>>;
