import { and, asc, desc, eq } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import { ExperimentKey } from "@billet/contracts-domain/flags";
import { EpochMillis } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { FlagsUnavailable } from "@billet/backend-flags/flags-error";
import {
  FlagChange,
  FlagChangeAction,
  FlagConfig,
  PairOverride,
  type StoredFlagConfig,
} from "@billet/backend-flags/flag-config";
import {
  FlagConfigConflict,
  FlagConfigRepository,
} from "@billet/backend-flags/flag-config-repository";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { flagChanges, flagConfigs, pairFlagOverrides } from "./directory-schema.ts";

/** A `flag_configs` row as stored: the configuration is JSON text. */
export const FlagConfigRow = Schema.Struct({
  key: ExperimentKey,
  config: Schema.fromJsonString(FlagConfig),
  version: Schema.Int,
  updatedAt: EpochMillis,
  updatedBy: Schema.String,
});

/** A `flag_changes` row as stored. */
export const FlagChangeRow = Schema.Struct({
  id: Schema.Int,
  key: ExperimentKey,
  at: EpochMillis,
  by: Schema.String,
  action: FlagChangeAction,
  pairId: Schema.NullOr(PairId),
  before: Schema.NullOr(Schema.fromJsonString(Schema.Unknown)),
  after: Schema.NullOr(Schema.fromJsonString(Schema.Unknown)),
});

/** A `pair_flag_overrides` row. */
export const PairOverrideRow = PairOverride;

/**
 * The Cache API key the configurations are kept under at the edge. It is never fetched: the
 * Cache API needs a URL, and `.invalid` can never resolve.
 */
export const flagConfigCacheUrl = "https://flag-configs.billet.invalid/v1";

/** How long a colo may serve the configurations without asking D1. A kill reaches every colo within it. */
export const flagConfigCacheSeconds = 30;

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = () => new FlagsUnavailable({ reason: "directory-unavailable" });
const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodeConfigs = Schema.decodeUnknownEffect(Schema.Array(FlagConfigRow));
const decodeChanges = Schema.decodeUnknownEffect(Schema.Array(FlagChangeRow));
const decodeOverrides = Schema.decodeUnknownEffect(Schema.Array(PairOverrideRow));
const encodeConfig = Schema.encodeSync(Schema.fromJsonString(FlagConfig));
const decodeCached = Schema.decodeUnknownEffect(Schema.fromJsonString(Schema.Array(FlagConfigRow)));
const encodeCached = Schema.encodeSync(Schema.fromJsonString(Schema.Array(FlagConfigRow)));
const decodeBatchRow = Schema.decodeUnknownEffect(
  Schema.Array(
    Schema.Struct({
      key: ExperimentKey,
      config: Schema.fromJsonString(FlagConfig),
      version: Schema.Int,
      updated_at: EpochMillis,
      updated_by: Schema.String,
    }),
  ),
);

/** A raw statement for `atomically`, for the two that Drizzle's builder cannot express. */
const statement = (sql: string, params: ReadonlyArray<unknown>) => ({
  toSQL: () => ({ sql, params }),
});

const json = (value: unknown) =>
  value === null || value === undefined ? null : JSON.stringify(value);

const makeRepository = (
  db: DirectoryDatabase,
  cache: Cache | undefined,
): FlagConfigRepository["Service"] => {
  const fromDatabase = guarded(
    db.select().from(flagConfigs).orderBy(asc(flagConfigs.key)).pipe(Effect.flatMap(decodeConfigs)),
  );

  // A cache that fails is skipped, never fatal: the database is the truth.
  const cached: Effect.Effect<ReadonlyArray<StoredFlagConfig> | undefined> =
    cache === undefined
      ? Effect.succeed(undefined)
      : Effect.tryPromise(() => cache.match(flagConfigCacheUrl)).pipe(
          Effect.flatMap((hit) =>
            hit === undefined
              ? Effect.succeed(undefined)
              : Effect.tryPromise(() => hit.text()).pipe(Effect.flatMap(decodeCached)),
          ),
          Effect.orElseSucceed(() => undefined),
        );

  const remember = (rows: ReadonlyArray<StoredFlagConfig>) =>
    cache === undefined
      ? Effect.void
      : Effect.tryPromise(() =>
          cache.put(
            flagConfigCacheUrl,
            new Response(encodeCached(rows), {
              headers: {
                "content-type": "application/json",
                "cache-control": `max-age=${flagConfigCacheSeconds}`,
              },
            }),
          ),
        ).pipe(Effect.ignore);

  // This colo sees a change at once; the others within `flagConfigCacheSeconds`.
  const forget =
    cache === undefined
      ? Effect.void
      : Effect.tryPromise(() => cache.delete(flagConfigCacheUrl)).pipe(Effect.ignore);

  const logChange = (change: Omit<FlagChange, "id">) =>
    db.insert(flagChanges).values({
      key: change.key,
      at: change.at,
      by: change.by,
      action: change.action,
      pairId: change.pairId ?? null,
      before: json(change.before),
      after: json(change.after),
    });

  return FlagConfigRepository.of({
    all: Effect.gen(function* () {
      const hit = yield* cached;
      if (hit !== undefined) return hit;
      const rows = yield* fromDatabase;
      yield* remember(rows);
      return rows;
    }),

    save: ({ key, config, expectedVersion, action, by, at }) =>
      Effect.gen(function* () {
        const before = yield* guarded(
          db
            .select()
            .from(flagConfigs)
            .where(eq(flagConfigs.key, key))
            .pipe(Effect.flatMap(decodeConfigs)),
        );
        const current = before[0]?.version ?? 0;
        if (current !== expectedVersion) return yield* new FlagConfigConflict({ current });
        const text = encodeConfig(config);
        const next = expectedVersion + 1;
        // The update and the history line succeed together or not at all. The version check is
        // repeated inside the batch, so of two saves from one version only one lands.
        const results = yield* guarded(
          atomically(db, [
            statement(
              `INSERT INTO flag_configs (key, config, version, updated_at, updated_by)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT (key) DO UPDATE SET config = excluded.config, version = excluded.version,
                 updated_at = excluded.updated_at, updated_by = excluded.updated_by
               WHERE flag_configs.version = ?`,
              [key, text, next, at, by, expectedVersion],
            ),
            statement(
              `INSERT INTO flag_changes (key, at, by, action, pair_id, before, after)
               SELECT ?, ?, ?, ?, NULL, ?, ?
               WHERE EXISTS (SELECT 1 FROM flag_configs WHERE key = ? AND version = ?
                 AND updated_at = ? AND updated_by = ? AND config = ?)`,
              [key, at, by, action, json(before[0]?.config), text, key, next, at, by, text],
            ),
            statement(
              "SELECT key, config, version, updated_at, updated_by FROM flag_configs WHERE key = ?",
              [key],
            ),
          ]),
        );
        const [row] = yield* guarded(decodeBatchRow(results[2]));
        if (
          row === undefined ||
          row.version !== next ||
          row.updated_at !== at ||
          row.updated_by !== by
        ) {
          return yield* new FlagConfigConflict({ current: row?.version ?? 0 });
        }
        yield* forget;
        return {
          key: row.key,
          config: row.config,
          version: row.version,
          updatedAt: row.updated_at,
          updatedBy: row.updated_by,
        };
      }),

    history: (key, limit) =>
      guarded(
        db
          .select()
          .from(flagChanges)
          .where(key === undefined ? undefined : eq(flagChanges.key, key))
          .orderBy(desc(flagChanges.id))
          .limit(limit)
          .pipe(
            Effect.flatMap(decodeChanges),
            Effect.map((rows) =>
              rows.map(({ pairId, ...rest }) => (pairId === null ? rest : { ...rest, pairId })),
            ),
          ),
      ),

    overridesOf: (pairId) =>
      guarded(
        db
          .select()
          .from(pairFlagOverrides)
          .where(eq(pairFlagOverrides.pairId, pairId))
          .orderBy(asc(pairFlagOverrides.experimentKey))
          .pipe(Effect.flatMap(decodeOverrides)),
      ),

    setOverride: (override) =>
      Effect.gen(function* () {
        const before = yield* guarded(
          db
            .select()
            .from(pairFlagOverrides)
            .where(
              and(
                eq(pairFlagOverrides.pairId, override.pairId),
                eq(pairFlagOverrides.experimentKey, override.experimentKey),
              ),
            )
            .pipe(Effect.flatMap(decodeOverrides)),
        );
        yield* guarded(
          atomically(db, [
            db
              .insert(pairFlagOverrides)
              .values(override)
              .onConflictDoUpdate({
                target: [pairFlagOverrides.pairId, pairFlagOverrides.experimentKey],
                set: { variant: override.variant, setAt: override.setAt, setBy: override.setBy },
              }),
            logChange({
              key: override.experimentKey,
              at: override.setAt,
              by: override.setBy,
              action: "override",
              pairId: override.pairId,
              before: before[0] === undefined ? null : { variant: before[0].variant },
              after: { variant: override.variant },
            }),
          ]),
        );
      }),

    clearOverride: ({ pairId, experimentKey, by, at }) =>
      Effect.gen(function* () {
        const where = and(
          eq(pairFlagOverrides.pairId, pairId),
          eq(pairFlagOverrides.experimentKey, experimentKey),
        );
        const before = yield* guarded(
          db.select().from(pairFlagOverrides).where(where).pipe(Effect.flatMap(decodeOverrides)),
        );
        const existing = before[0];
        if (existing === undefined) return;
        yield* guarded(
          atomically(db, [
            db.delete(pairFlagOverrides).where(where),
            logChange({
              key: experimentKey,
              at,
              by,
              action: "clear-override",
              pairId,
              before: { variant: existing.variant },
              after: null,
            }),
          ]),
        );
      }),
  });
};

/**
 * `FlagConfigRepository` on the D1 directory, with `all` cached in `cache` (the colo's Cache API)
 * for `flagConfigCacheSeconds`. Build it once per request, as `openDirectoryDatabase` asks.
 */
export const FlagConfigRepositoryLive = (
  binding: D1Database,
  cache: Cache | undefined,
): Layer.Layer<FlagConfigRepository> =>
  Layer.effect(
    FlagConfigRepository,
    Effect.map(openDirectoryDatabase(binding), (db) => makeRepository(db, cache)),
  );
