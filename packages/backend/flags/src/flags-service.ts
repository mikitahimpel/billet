import { Clock, Context, Effect, Layer, Option } from "effect";
import { Digest } from "effect/crypto";
import type { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { FlagsResponse } from "@billet/contracts-http-api/flags";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { assign } from "./assignment.ts";
import { Experiments } from "./experiments.ts";
import { FlagsUnavailable } from "./flags-error.ts";
import { FlagsRepository, type StoredAssignment } from "./flags-repository.ts";

/** The experiment variants of a pair. Routes never see the repository. */
export class FlagsService extends Context.Service<
  FlagsService,
  {
    /** The caller's pair's variants. A caller without a partner is in no experiment: none listed. */
    readonly flagsFor: (userId: UserId) => Effect.Effect<FlagsResponse, FlagsUnavailable>;
    /**
     * Gives a pair its variants and stores the ones that put it in an experiment. Pairing calls it
     * so the choice exists from the first moment; reading flags does the same for a pair that
     * predates an experiment, so a failure here loses nothing.
     */
    readonly assignPair: (pairId: PairId) => Effect.Effect<void, FlagsUnavailable>;
  }
>()("@billet/backend-flags/FlagsService") {
  static readonly layer: Layer.Layer<
    FlagsService,
    never,
    PairingRepository | FlagsRepository | Experiments | Digest.Digest
  > = Layer.effect(
    FlagsService,
    Effect.gen(function* () {
      const pairing = yield* PairingRepository;
      const repository = yield* FlagsRepository;
      const experiments = yield* Experiments;
      const digest = yield* Digest.Digest;

      const flagsOfPair = Effect.fnUntraced(function* (
        pairId: PairId,
      ): Effect.fn.Return<FlagsResponse["flags"], FlagsUnavailable> {
        const running = experiments.filter(({ killed }) => !killed);
        if (running.length === 0) return [];

        const stored = yield* repository.find(pairId);
        const kept = new Map<ExperimentKey, VariantId>(
          stored.map(({ experimentKey, variant }) => [experimentKey, variant]),
        );

        // Only a pair that is inside an experiment is stored. A pair outside it is worked out
        // again each time, from the same hash, so raising exposure later brings pairs in without
        // moving the ones already in.
        const entering: Array<StoredAssignment> = [];
        const assignedAt = yield* Clock.currentTimeMillis;
        for (const experiment of running) {
          if (kept.has(experiment.key)) continue;
          const result = yield* assign(experiment, pairId).pipe(
            Effect.provideService(Digest.Digest, digest),
          );
          if (result.exposed) {
            entering.push({
              pairId,
              experimentKey: experiment.key,
              variant: result.variant,
              assignedAt,
            });
          }
        }
        const now =
          entering.length === 0 ? stored : yield* repository.saveMissing(pairId, entering);
        const final = new Map(now.map(({ experimentKey, variant }) => [experimentKey, variant]));

        const flags: Array<FlagsResponse["flags"][number]> = [];
        for (const experiment of running) {
          const given = final.get(experiment.key);
          // A variant the registry no longer lists was retired: the pair gets the default, not a new roll.
          const known = experiment.variants.some(({ id }) => id === given);
          flags.push({
            key: experiment.key,
            variant: given !== undefined && known ? given : experiment.default,
          });
        }
        return flags;
      });

      const flagsFor = Effect.fnUntraced(function* (
        userId: UserId,
      ): Effect.fn.Return<FlagsResponse, FlagsUnavailable> {
        const pairId = yield* pairing
          .findPair(userId)
          .pipe(Effect.mapError(() => new FlagsUnavailable({ reason: "directory-unavailable" })));
        if (Option.isNone(pairId)) return { flags: [] };
        return { flags: yield* flagsOfPair(pairId.value) };
      });

      const assignPair = (pairId: PairId) => Effect.asVoid(flagsOfPair(pairId));

      return FlagsService.of({ flagsFor, assignPair });
    }),
  );
}
