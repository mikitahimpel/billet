// The partner's APNs tokens, read from the D1 directory for the room's push lanes.
import { and, eq } from "drizzle-orm";
import { Effect } from "effect";
import type { ApnsEnvironment } from "./apns-client.ts";
import type { DeviceToken } from "./apns-lanes.ts";
import { openDirectoryDatabase } from "./directory-database.ts";
import { devices, pushTokens } from "./directory-schema.ts";

const environmentOf = (value: string): ApnsEnvironment =>
  value === "sandbox" ? "sandbox" : "production";

/** Every token of `kind` on any of `user`'s devices. */
export const tokensOf = (binding: D1Database, user: string, kind: string) =>
  Effect.runPromise(
    Effect.scoped(
      Effect.gen(function* () {
        const db = yield* openDirectoryDatabase(binding);
        const rows = yield* db
          .select({ token: pushTokens.token, environment: pushTokens.environment })
          .from(pushTokens)
          .innerJoin(devices, eq(devices.id, pushTokens.deviceId))
          .where(and(eq(devices.userId, user), eq(pushTokens.kind, kind)))
          .pipe(Effect.orDie);
        return rows.map((row): DeviceToken => ({
          token: row.token,
          environment: environmentOf(row.environment),
        }));
      }),
    ),
  );

/** Forgets a token APNs called dead, so it is not tried again. */
export const dropToken = (binding: D1Database, token: string, kind: string) =>
  Effect.runPromise(
    Effect.scoped(
      Effect.gen(function* () {
        const db = yield* openDirectoryDatabase(binding);
        yield* db
          .delete(pushTokens)
          .where(and(eq(pushTokens.token, token), eq(pushTokens.kind, kind)))
          .pipe(Effect.asVoid, Effect.orDie);
      }),
    ),
  );
