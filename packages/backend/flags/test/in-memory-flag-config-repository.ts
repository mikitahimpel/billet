import { Effect } from "effect";
import { FlagConfigConflict, type FlagConfigRepository } from "../src/flag-config-repository.ts";
import type { FlagChange, PairOverride, StoredFlagConfig } from "../src/flag-config.ts";

/** The test double for `FlagConfigRepository`. Single-threaded, so each method is atomic. */
export const makeInMemoryFlagConfigRepository = () => {
  const configs = new Map<string, StoredFlagConfig>();
  const changes: Array<FlagChange> = [];
  const overrides = new Map<string, PairOverride>();
  const log = (change: Omit<FlagChange, "id">) =>
    changes.push({ ...change, id: changes.length + 1 });

  const repository: FlagConfigRepository["Service"] = {
    all: Effect.sync(() => [...configs.values()]),
    save: ({ key, config, expectedVersion, action, by, at }) =>
      Effect.suspend(() => {
        const before = configs.get(key);
        const current = before?.version ?? 0;
        if (current !== expectedVersion) return Effect.fail(new FlagConfigConflict({ current }));
        const saved = { key, config, version: current + 1, updatedAt: at, updatedBy: by };
        configs.set(key, saved);
        log({ key, at, by, action, before: before?.config ?? null, after: config });
        return Effect.succeed(saved);
      }),
    history: (key, limit) =>
      Effect.sync(() =>
        changes
          .filter((change) => key === undefined || change.key === key)
          .toReversed()
          .slice(0, limit),
      ),
    overridesOf: (pairId) =>
      Effect.sync(() => [...overrides.values()].filter((row) => row.pairId === pairId)),
    setOverride: (override) =>
      Effect.sync(() => {
        const id = `${override.pairId}/${override.experimentKey}`;
        const before = overrides.get(id);
        overrides.set(id, override);
        log({
          key: override.experimentKey,
          at: override.setAt,
          by: override.setBy,
          action: "override",
          pairId: override.pairId,
          before: before === undefined ? null : { variant: before.variant },
          after: { variant: override.variant },
        });
      }),
    clearOverride: ({ pairId, experimentKey, by, at }) =>
      Effect.sync(() => {
        const id = `${pairId}/${experimentKey}`;
        const before = overrides.get(id);
        if (before === undefined) return;
        overrides.delete(id);
        log({
          key: experimentKey,
          at,
          by,
          action: "clear-override",
          pairId,
          before: { variant: before.variant },
          after: null,
        });
      }),
  };
  return { repository, configs, changes, overrides };
};
