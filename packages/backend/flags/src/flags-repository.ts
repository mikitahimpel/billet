import { Context, type Effect, Schema } from "effect";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { EpochMillis } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { FlagsUnavailable } from "./flags-error.ts";

/**
 * What a `pair_flags` row holds: the variant a pair was given when it entered an experiment. A
 * test in `platform` fails if the table's columns differ.
 */
export const StoredAssignment = Schema.Struct({
  pairId: PairId,
  experimentKey: ExperimentKey,
  variant: VariantId,
  assignedAt: EpochMillis,
});
export type StoredAssignment = typeof StoredAssignment.Type;

/**
 * Persistence for assignments. Only pairs that entered an experiment are stored, and a stored
 * assignment is never changed, so editing weights or exposure later moves nobody who is in.
 * `test/flags-repository-contract.ts` is the behaviour any implementation must pass.
 */
export class FlagsRepository extends Context.Service<
  FlagsRepository,
  {
    readonly find: (
      pairId: PairId,
    ) => Effect.Effect<ReadonlyArray<StoredAssignment>, FlagsUnavailable>;
    /**
     * Stores each assignment the pair does not already have for that experiment, leaves the others
     * as they are, and returns everything the pair now has. Safe to call from both partners at once.
     */
    readonly saveMissing: (
      pairId: PairId,
      assignments: ReadonlyArray<StoredAssignment>,
    ) => Effect.Effect<ReadonlyArray<StoredAssignment>, FlagsUnavailable>;
  }
>()("@billet/backend-flags/FlagsRepository") {}
