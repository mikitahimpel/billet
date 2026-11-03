import { Effect } from "effect";
import { normalStatus } from "@billet/contracts-http-api/status";
import {
  type AppStatusChange,
  AppStatusConflict,
  AppStatusStore,
  type StoredAppStatus,
} from "../src/app-status-store.ts";

/** The status store in memory, for tests: same version check as the KV one. */
export const makeInMemoryAppStatusStore = () => {
  let stored: StoredAppStatus = {
    status: normalStatus,
    version: 0,
    updatedAt: null,
    updatedBy: null,
  };
  let changes: Array<AppStatusChange> = [];
  const store = AppStatusStore.of({
    current: Effect.sync(() => stored),
    history: (limit) => Effect.sync(() => changes.slice(0, limit)),
    save: ({ status, expectedVersion, by, at }) =>
      Effect.suspend(() => {
        if (expectedVersion !== stored.version) {
          return Effect.fail(new AppStatusConflict({ current: stored.version }));
        }
        stored = { status, version: stored.version + 1, updatedAt: at, updatedBy: by };
        changes = [{ version: stored.version, at, by, status }, ...changes];
        return Effect.succeed(stored);
      }),
  });
  return { store };
};
