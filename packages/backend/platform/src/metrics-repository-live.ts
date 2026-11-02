import { asc, sql } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import { MetricsUnavailable } from "@billet/backend-metrics/metrics-error";
import { MetricsRepository, StoredMetric } from "@billet/backend-metrics/metrics-repository";
import { type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { pairEvents } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = () => new MetricsUnavailable({ reason: "directory-unavailable" });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodeRows = Schema.decodeUnknownEffect(Schema.Array(StoredMetric));

const dayOf = (millis: number): string => new Date(millis).toISOString().slice(0, 10);

const makeMetricsRepository = (db: DirectoryDatabase): MetricsRepository["Service"] =>
  MetricsRepository.of({
    // One statement: the add happens in the database, so two at once both count.
    record: ({ pairId, userId, name, at }) =>
      guarded(
        db
          .insert(pairEvents)
          .values({ pairId, userId, name, day: dayOf(at), count: 1, firstAt: at, lastAt: at })
          .onConflictDoUpdate({
            target: [pairEvents.pairId, pairEvents.userId, pairEvents.name, pairEvents.day],
            set: {
              count: sql`${pairEvents.count} + 1`,
              lastAt: sql`max(${pairEvents.lastAt}, ${at})`,
            },
          }),
      ).pipe(Effect.asVoid),
    all: guarded(
      db
        .select()
        .from(pairEvents)
        .orderBy(asc(pairEvents.day), asc(pairEvents.pairId))
        .pipe(Effect.flatMap(decodeRows)),
    ),
  });

/** `MetricsRepository` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const MetricsRepositoryLive = (binding: D1Database): Layer.Layer<MetricsRepository> =>
  Layer.effect(
    MetricsRepository,
    Effect.map(openDirectoryDatabase(binding), makeMetricsRepository),
  );
