import { asc, sql } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import { utcDay } from "@billet/backend-metrics/metrics";
import { MetricsUnavailable } from "@billet/backend-metrics/metrics-error";
import {
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

const makeMetricsRepository = (db: DirectoryDatabase): MetricsRepository["Service"] =>
  MetricsRepository.of(
    spanMethods("MetricsRepository", {
      // One statement per table: the add happens in the database, so two at once both count.
      record: ({ pairId, userId, name, at, detail, value, client }) => {
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
              // The day's latest report wins; a report without them keeps what is there.
              appVersion: sql`coalesce(excluded.app_version, ${pairEvents.appVersion})`,
              os: sql`coalesce(excluded.os, ${pairEvents.os})`,
            },
          });
        if (detail === undefined) return guarded(person).pipe(Effect.asVoid);
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
        return guarded(atomically(db, [person, thing])).pipe(Effect.asVoid);
      },
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

/** `MetricsRepository` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const MetricsRepositoryLive = (binding: D1Database): Layer.Layer<MetricsRepository> =>
  Layer.effect(
    MetricsRepository,
    Effect.map(openDirectoryDatabase(binding), makeMetricsRepository),
  );
