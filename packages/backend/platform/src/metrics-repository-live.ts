import { asc, sql } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import { utcDay } from "@billet/backend-metrics/metrics";
import { MetricsUnavailable } from "@billet/backend-metrics/metrics-error";
import {
  type MetricOccurrence,
  MetricsRepository,
  StoredDetail,
  StoredMetric,
} from "@billet/backend-metrics/metrics-repository";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { eventDetails, pairEvents } from "./directory-schema.ts";
import { spanMethods } from "@billet/backend-observability/span-methods";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = (cause: unknown) =>
  new MetricsUnavailable({ reason: "directory-unavailable", cause });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodeRows = Schema.decodeUnknownEffect(Schema.Array(StoredMetric));
const decodeDetails = Schema.decodeUnknownEffect(Schema.Array(StoredDetail));

const statementsOf =
  (db: DirectoryDatabase) =>
  ({ pairId, userId, name, at, detail, value, client }: MetricOccurrence) => {
    const day = utcDay(at);
    const appVersion = client?.appVersion ?? null;
    const os = client?.os ?? null;
    const person = db
      .insert(pairEvents)
      .values({ pairId, userId, name, day, count: 1, firstAt: at, lastAt: at, appVersion, os })
      .onConflictDoUpdate({
        target: [pairEvents.pairId, pairEvents.userId, pairEvents.name, pairEvents.day],
        set: {
          count: sql`${pairEvents.count} + 1`,
          lastAt: sql`max(${pairEvents.lastAt}, ${at})`,
          // A report without client info keeps what is there.
          appVersion: sql`coalesce(excluded.app_version, ${pairEvents.appVersion})`,
          os: sql`coalesce(excluded.os, ${pairEvents.os})`,
        },
      });
    if (detail === undefined) return [person];
    const total = value ?? 0;
    const thing = db
      .insert(eventDetails)
      .values({ name, detail, day, count: 1, total })
      .onConflictDoUpdate({
        target: [eventDetails.name, eventDetails.detail, eventDetails.day],
        set: {
          count: sql`${eventDetails.count} + 1`,
          total: sql`${eventDetails.total} + ${total}`,
        },
      });
    return [person, thing];
  };

const makeMetricsRepository = (db: DirectoryDatabase): MetricsRepository["Service"] => {
  const statements = statementsOf(db);
  return MetricsRepository.of(
    spanMethods("MetricsRepository", {
      // The add happens in the database, so two concurrent records both count.
      record: (occurrence) => guarded(atomically(db, statements(occurrence))).pipe(Effect.asVoid),
      // One D1 round trip for the whole report instead of one per event; all or none.
      recordMany: (occurrences) =>
        occurrences.length === 0
          ? Effect.void
          : guarded(atomically(db, occurrences.flatMap(statements))).pipe(Effect.asVoid),
      all: guarded(
        db
          .select()
          .from(pairEvents)
          .orderBy(asc(pairEvents.day), asc(pairEvents.pairId))
          .pipe(Effect.flatMap(decodeRows)),
      ),
      details: guarded(
        db
          .select()
          .from(eventDetails)
          .orderBy(asc(eventDetails.day), asc(eventDetails.name))
          .pipe(Effect.flatMap(decodeDetails)),
      ),
    }),
  );
};

/** Build it once per request, as `openDirectoryDatabase` asks. */
export const MetricsRepositoryLive = (binding: D1Database): Layer.Layer<MetricsRepository> =>
  Layer.effect(
    MetricsRepository,
    Effect.map(openDirectoryDatabase(binding), makeMetricsRepository),
  );
