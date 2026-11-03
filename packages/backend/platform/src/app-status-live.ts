import { Effect, Layer, Schema } from "effect";
import {
  type AppStatusChange,
  AppStatusConflict,
  AppStatusStore,
  AppStatusUnavailable,
  type StoredAppStatus,
} from "@billet/backend-admin/app-status-store";
import { AppStatus, normalStatus } from "@billet/contracts-http-api/status";

/**
 * The service status lives in Workers KV, not D1: maintenance has to be switched on, and served,
 * while the database or the rest of the API is down. Two keys: the current status with its version,
 * and the last changes, newest first.
 */
export const statusKey = "app-status";
export const statusHistoryKey = "app-status-history";
const historyLength = 200;

/**
 * How long a Worker location keeps a read before asking KV again: the shortest KV allows. A change
 * reaches every app within about this plus KV's own propagation (up to a minute).
 */
export const statusCacheSeconds = 30;

const Stored = Schema.Struct({
  status: AppStatus,
  version: Schema.Int,
  updatedAt: Schema.Number,
  updatedBy: Schema.String,
});
const History = Schema.Array(
  Schema.Struct({ version: Schema.Int, at: Schema.Number, by: Schema.String, status: AppStatus }),
);
const decodeStored = Schema.decodeUnknownOption(Stored);
const decodeHistory = Schema.decodeUnknownOption(History);

const never: StoredAppStatus = {
  status: normalStatus,
  version: 0,
  updatedAt: null,
  updatedBy: null,
};

/**
 * The status every request is answered under. Read before anything touches D1 and cached at the
 * location for `statusCacheSeconds`. No binding, an unreadable value or a KV failure all read as
 * the normal status, so a KV problem never takes the API down.
 */
export const readServedStatus = async (kv: KVNamespace | undefined): Promise<AppStatus> => {
  if (kv === undefined) return normalStatus;
  try {
    const raw = await kv.get(statusKey, { type: "json", cacheTtl: statusCacheSeconds });
    if (raw === null) return normalStatus;
    const stored = decodeStored(raw);
    if (stored._tag === "Some") return stored.value.status;
    console.warn("app status unreadable");
    return normalStatus;
  } catch {
    console.warn("app status unavailable");
    return normalStatus;
  }
};

const attempt = <A>(reason: string, run: () => Promise<A>) =>
  Effect.tryPromise({ try: run, catch: () => new AppStatusUnavailable({ reason }) });

/**
 * The admin panel's view: read without the location cache, so a save shows at once. KV has no
 * transactions; the version check stops a stale tab, which is all one owner needs.
 */
export const AppStatusStoreLive = (kv: KVNamespace | undefined) =>
  Layer.succeed(
    AppStatusStore,
    (() => {
      if (kv === undefined) {
        const missing = Effect.fail(new AppStatusUnavailable({ reason: "not-bound" }));
        return AppStatusStore.of({ current: missing, history: () => missing, save: () => missing });
      }
      const current = attempt("read", () => kv.get(statusKey, { type: "json" })).pipe(
        Effect.map((raw): StoredAppStatus => {
          if (raw === null) return never;
          const stored = decodeStored(raw);
          return stored._tag === "Some" ? stored.value : never;
        }),
      );
      const history = (limit: number) =>
        attempt("read-history", () => kv.get(statusHistoryKey, { type: "json" })).pipe(
          Effect.map((raw): ReadonlyArray<AppStatusChange> => {
            const decoded = decodeHistory(raw ?? []);
            return decoded._tag === "Some" ? decoded.value.slice(0, limit) : [];
          }),
        );
      return AppStatusStore.of({
        current,
        history,
        save: ({ status, expectedVersion, by, at }) =>
          Effect.gen(function* () {
            const before = yield* current;
            if (before.version !== expectedVersion) {
              return yield* new AppStatusConflict({ current: before.version });
            }
            const saved = { status, version: before.version + 1, updatedAt: at, updatedBy: by };
            yield* attempt("write", () => kv.put(statusKey, JSON.stringify(saved)));
            // The status is what matters; a history that can't be written doesn't undo it.
            const past = yield* history(historyLength).pipe(Effect.orElseSucceed(() => []));
            const change: AppStatusChange = { version: saved.version, at, by, status };
            yield* attempt("write-history", () =>
              kv.put(statusHistoryKey, JSON.stringify([change, ...past].slice(0, historyLength))),
            ).pipe(Effect.catch(() => Effect.logWarning("app status history not written")));
            return saved;
          }),
      });
    })(),
  );
