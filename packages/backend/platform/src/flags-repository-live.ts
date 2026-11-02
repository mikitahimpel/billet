import { eq } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import { FlagsUnavailable } from "@billet/backend-flags/flags-error";
import { FlagsRepository, StoredAssignment } from "@billet/backend-flags/flags-repository";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { pairFlags } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = () => new FlagsUnavailable({ reason: "directory-unavailable" });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodeRows = Schema.decodeUnknownEffect(Schema.Array(StoredAssignment));
// A batch returns rows as stored, keyed by column name rather than by Drizzle field.
const decodeBatchRows = Schema.decodeUnknownEffect(
  Schema.Array(
    Schema.Struct({
      pair_id: StoredAssignment.fields.pairId,
      experiment_key: StoredAssignment.fields.experimentKey,
      variant: StoredAssignment.fields.variant,
      assigned_at: StoredAssignment.fields.assignedAt,
    }),
  ),
);

const makeFlagsRepository = (db: DirectoryDatabase): FlagsRepository["Service"] => {
  const find = (pairId: PairId) =>
    guarded(
      db
        .select()
        .from(pairFlags)
        .where(eq(pairFlags.pairId, pairId))
        .pipe(Effect.flatMap(decodeRows)),
    );

  return FlagsRepository.of({
    find,
    saveMissing: (pairId, assignments) => {
      if (assignments.length === 0) return find(pairId);
      return guarded(
        atomically(db, [
          db
            .insert(pairFlags)
            .values(
              assignments.map(({ experimentKey, variant, assignedAt }) => ({
                pairId,
                experimentKey,
                variant,
                assignedAt,
              })),
            )
            .onConflictDoNothing(),
          db.select().from(pairFlags).where(eq(pairFlags.pairId, pairId)),
        ]).pipe(Effect.flatMap((results) => decodeBatchRows(results[1]))),
      ).pipe(
        Effect.map((rows) =>
          rows.map((row) => ({
            pairId: row.pair_id,
            experimentKey: row.experiment_key,
            variant: row.variant,
            assignedAt: row.assigned_at,
          })),
        ),
      );
    },
  });
};

/** `FlagsRepository` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const FlagsRepositoryLive = (binding: D1Database): Layer.Layer<FlagsRepository> =>
  Layer.effect(FlagsRepository, Effect.map(openDirectoryDatabase(binding), makeFlagsRepository));
