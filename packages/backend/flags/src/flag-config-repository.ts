import { Context, Data, type Effect } from "effect";
import type { ExperimentKey } from "@billet/contracts-domain/flags";
import type { EpochMillis } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { FlagsUnavailable } from "./flags-error.ts";
import type {
  FlagChange,
  FlagChangeAction,
  FlagConfig,
  PairOverride,
  StoredFlagConfig,
} from "./flag-config.ts";

/** Someone saved first: the editor's version is behind. Reload and apply the change again. */
export class FlagConfigConflict extends Data.TaggedError("FlagConfigConflict")<{
  readonly current: number;
}> {}

export interface FlagConfigSave {
  readonly key: ExperimentKey;
  readonly config: FlagConfig;
  /** The version the editor started from; 0 when the key has never been saved. */
  readonly expectedVersion: number;
  readonly action: FlagChangeAction;
  readonly by: string;
  readonly at: EpochMillis;
}

/**
 * What the admin panel writes: the live configuration of each registry entry, its history, and
 * per-pair overrides. Every write adds a history line in the same transaction.
 * `test/flag-config-repository-contract.ts` is the behaviour any implementation must pass.
 */
export class FlagConfigRepository extends Context.Service<
  FlagConfigRepository,
  {
    /** Every saved configuration. Read on each flags request, so the live one caches it briefly. */
    readonly all: Effect.Effect<ReadonlyArray<StoredFlagConfig>, FlagsUnavailable>;
    readonly save: (
      change: FlagConfigSave,
    ) => Effect.Effect<StoredFlagConfig, FlagsUnavailable | FlagConfigConflict>;
    /** Newest first. One key's, or everyone's. */
    readonly history: (
      key: ExperimentKey | undefined,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<FlagChange>, FlagsUnavailable>;
    readonly overridesOf: (
      pairId: PairId,
    ) => Effect.Effect<ReadonlyArray<PairOverride>, FlagsUnavailable>;
    readonly setOverride: (override: PairOverride) => Effect.Effect<void, FlagsUnavailable>;
    readonly clearOverride: (change: {
      readonly pairId: PairId;
      readonly experimentKey: ExperimentKey;
      readonly by: string;
      readonly at: EpochMillis;
    }) => Effect.Effect<void, FlagsUnavailable>;
  }
>()("@billet/backend-flags/FlagConfigRepository") {}
