import { Effect } from "effect";
import type { MetricsRepository, StoredDetail, StoredMetric } from "../src/metrics-repository.ts";

/** The test double for `MetricsRepository`. Single-threaded, so each method is trivially atomic. */
export const makeInMemoryMetricsRepository = () => {
  const rows = new Map<string, StoredMetric>();
  const details = new Map<string, StoredDetail>();
  const repository: MetricsRepository["Service"] = {
    recordMany: (occurrences) =>
      Effect.forEach(occurrences, (occurrence) => repository.record(occurrence), {
        discard: true,
      }),
    record: ({ pairId, userId, name, at, detail, value, client }) =>
      Effect.sync(() => {
        const day = new Date(at).toISOString().slice(0, 10);
        const key = [pairId, userId, name, day].join("/");
        const existing = rows.get(key);
        rows.set(
          key,
          existing === undefined
            ? {
                pairId,
                userId,
                name,
                day,
                count: 1,
                firstAt: at,
                lastAt: at,
                appVersion: client?.appVersion ?? null,
                os: client?.os ?? null,
              }
            : {
                ...existing,
                count: existing.count + 1,
                lastAt: Math.max(existing.lastAt, at),
                appVersion: client?.appVersion ?? existing.appVersion,
                os: client?.os ?? existing.os,
              },
        );
        if (detail === undefined) return;
        const detailKey = [name, detail, day].join("/");
        const counted = details.get(detailKey);
        details.set(
          detailKey,
          counted === undefined
            ? { name, detail, day, count: 1, total: value ?? 0 }
            : { ...counted, count: counted.count + 1, total: counted.total + (value ?? 0) },
        );
      }),
    all: Effect.sync(() => [...rows.values()].toSorted((a, b) => a.day.localeCompare(b.day))),
    details: Effect.sync(() =>
      [...details.values()].toSorted((a, b) => a.day.localeCompare(b.day)),
    ),
  };
  return { repository, rows, details };
};
