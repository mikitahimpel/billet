import { Effect } from "effect";
import type { MetricsRepository, StoredMetric } from "../src/metrics-repository.ts";

/** The test double for `MetricsRepository`. Single-threaded, so each method is trivially atomic. */
export const makeInMemoryMetricsRepository = () => {
  const rows = new Map<string, StoredMetric>();
  const repository: MetricsRepository["Service"] = {
    record: ({ pairId, userId, name, at }) =>
      Effect.sync(() => {
        const day = new Date(at).toISOString().slice(0, 10);
        const key = [pairId, userId, name, day].join("/");
        const existing = rows.get(key);
        rows.set(
          key,
          existing === undefined
            ? { pairId, userId, name, day, count: 1, firstAt: at, lastAt: at }
            : { ...existing, count: existing.count + 1, lastAt: Math.max(existing.lastAt, at) },
        );
      }),
    all: Effect.sync(() => [...rows.values()].toSorted((a, b) => a.day.localeCompare(b.day))),
  };
  return { repository, rows };
};
