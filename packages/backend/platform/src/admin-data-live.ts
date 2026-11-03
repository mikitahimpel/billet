import { asc, count, eq, min } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import { AdminData, AdminUnavailable } from "@billet/backend-admin/admin-data";
import { MetricEventName } from "@billet/contracts-domain/metrics";
import { openDirectoryDatabase, type DirectoryDatabase } from "./directory-database.ts";
import { pairEvents, pairFlags, pairMembers, users } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const guarded = <A, E>(effect: Effect.Effect<A, E>) =>
  Effect.mapError(effect, () => new AdminUnavailable({ reason: "directory-unavailable" }));

const decodeEvents = Schema.decodeUnknownEffect(
  Schema.Array(
    Schema.Struct({
      pairId: Schema.String,
      userId: Schema.String,
      name: MetricEventName,
      day: Schema.String,
      count: Schema.Int,
      firstAt: Schema.Int,
    }),
  ),
);

const makeAdminData = (db: DirectoryDatabase): AdminData["Service"] =>
  AdminData.of({
    // Only the columns the funnel needs; `pair_events` holds no content in any case.
    events: guarded(
      db
        .select({
          pairId: pairEvents.pairId,
          userId: pairEvents.userId,
          name: pairEvents.name,
          day: pairEvents.day,
          count: pairEvents.count,
          firstAt: pairEvents.firstAt,
        })
        .from(pairEvents)
        .orderBy(asc(pairEvents.day))
        .pipe(Effect.flatMap(decodeEvents)),
    ),
    assignments: guarded(
      db
        .select({
          pairId: pairFlags.pairId,
          experimentKey: pairFlags.experimentKey,
          variant: pairFlags.variant,
        })
        .from(pairFlags),
    ),
    // A count, never the rows: the users table holds the Apple subject.
    userCount: guarded(
      db
        .select({ total: count() })
        .from(users)
        .pipe(Effect.map((rows) => rows[0]?.total ?? 0)),
    ),
    pair: (pairId) =>
      guarded(
        db
          .select({ members: count(), pairedAt: min(pairMembers.createdAt) })
          .from(pairMembers)
          .where(eq(pairMembers.pairId, pairId))
          .pipe(
            Effect.map((rows) => ({
              members: rows[0]?.members ?? 0,
              pairedAt: rows[0]?.pairedAt ?? null,
            })),
          ),
      ),
  });

/** `AdminData` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const AdminDataLive = (binding: D1Database): Layer.Layer<AdminData> =>
  Layer.effect(AdminData, Effect.map(openDirectoryDatabase(binding), makeAdminData));
