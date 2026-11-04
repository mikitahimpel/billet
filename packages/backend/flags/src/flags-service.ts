import { Clock, Context, Effect, Layer, Option } from "effect";
import { Digest } from "effect/crypto";
import type { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { unknownClient } from "@billet/contracts-http-api/client-info";
import type { FlagsResponse } from "@billet/contracts-http-api/flags";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { assign } from "./assignment.ts";
import { type Experiment, Experiments } from "./experiments.ts";
import { effectiveExperiments } from "./flag-config.ts";
import { FlagConfigRepository } from "./flag-config-repository.ts";
import { FlagsUnavailable } from "./flags-error.ts";
import { FlagsRepository, type StoredAssignment } from "./flags-repository.ts";
import { type FlagContext, isTargeted } from "./targeting.ts";

/** What the caller's request says about it, besides who it is. */
export interface CallerContext {
  readonly appVersion: string;
}

/** Why a pair gets what it gets in one experiment, for the admin's pair lookup. */
export type FlagReason =
  | "killed"
  | "override"
  | "draft"
  | "stored"
  | "stored-retired"
  | "stopped"
  | "not-targeted"
  | "entered"
  | "outside-exposure";

export interface FlagDecision {
  readonly key: ExperimentKey;
  /** What the pair is sent, or absent when the experiment is not listed for it. */
  readonly variant: VariantId | undefined;
  readonly reason: FlagReason;
}

const known = (experiment: Experiment, variant: VariantId | undefined) =>
  variant !== undefined && experiment.variants.some(({ id }) => id === variant);

/** The experiment variants of a pair. Routes never see the repositories. */
export class FlagsService extends Context.Service<
  FlagsService,
  {
    /** The caller's pair's variants. A caller without a partner is in no experiment: none listed. */
    readonly flagsFor: (
      userId: UserId,
      caller: CallerContext,
    ) => Effect.Effect<FlagsResponse, FlagsUnavailable>;
    /**
     * Gives a pair its variants and stores the ones that put it in an experiment. Pairing calls it
     * so the choice exists from the first moment; reading flags does the same for a pair that
     * predates an experiment, so a failure here loses nothing. Pairing does not know the build,
     * so an experiment targeted by app version waits for the pair's first flags read.
     */
    readonly assignPair: (pairId: PairId) => Effect.Effect<void, FlagsUnavailable>;
    /** Every experiment as configured now: the registry with the admin's saved changes. */
    readonly current: Effect.Effect<ReadonlyArray<Experiment>, FlagsUnavailable>;
    /**
     * What the pair would be sent and why, without storing anything. For the admin panel, which
     * does not know the pair's build: version targeting is judged on `appVersion`.
     */
    readonly explain: (
      pairId: PairId,
      appVersion: string,
    ) => Effect.Effect<ReadonlyArray<FlagDecision>, FlagsUnavailable>;
  }
>()("@billet/backend-flags/FlagsService") {
  static readonly layer: Layer.Layer<
    FlagsService,
    never,
    PairingRepository | FlagsRepository | FlagConfigRepository | Experiments | Digest.Digest
  > = Layer.effect(
    FlagsService,
    Effect.gen(function* () {
      const pairing = yield* PairingRepository;
      const repository = yield* FlagsRepository;
      const configs = yield* FlagConfigRepository;
      const registry = yield* Experiments;
      const digest = yield* Digest.Digest;

      const current = configs.all.pipe(
        Effect.map((stored) => effectiveExperiments(registry, stored)),
      );

      /**
       * One pass over the experiments. The kill switch beats everything; then an override; a
       * draft is for overrides only; a stored variant is kept (a retired one becomes the default);
       * a stopped experiment takes nobody new; targeting decides who may enter; exposure decides
       * who is analysed. `store` is false for a dry run.
       */
      const decide = Effect.fnUntraced(function* (
        context: FlagContext,
        store: boolean,
      ): Effect.fn.Return<ReadonlyArray<FlagDecision>, FlagsUnavailable> {
        const experiments = yield* current;
        const live = experiments.filter(({ killed }) => !killed);
        if (live.length === 0) {
          return experiments.map(({ key }) => ({ key, variant: undefined, reason: "killed" }));
        }

        const overrides = new Map(
          (yield* configs.overridesOf(context.pairId)).map(({ experimentKey, variant }) => [
            experimentKey,
            variant,
          ]),
        );
        const stored = yield* repository.find(context.pairId);
        const kept = new Map<ExperimentKey, VariantId>(
          stored.map(({ experimentKey, variant }) => [experimentKey, variant]),
        );

        // Only a pair that is inside an experiment is stored. A pair outside it is worked out
        // again each time, from the same hash, so raising exposure later brings pairs in without
        // moving the ones already in.
        const decisions: Array<FlagDecision> = [];
        const entering: Array<StoredAssignment> = [];
        const assignedAt = yield* Clock.currentTimeMillis;
        for (const experiment of experiments) {
          const { key } = experiment;
          const override = overrides.get(key);
          const given = kept.get(key);
          if (experiment.killed) {
            decisions.push({ key, variant: undefined, reason: "killed" });
          } else if (override !== undefined && known(experiment, override)) {
            decisions.push({ key, variant: override, reason: "override" });
          } else if (experiment.status === "draft") {
            decisions.push({ key, variant: undefined, reason: "draft" });
          } else if (given !== undefined) {
            decisions.push(
              known(experiment, given)
                ? { key, variant: given, reason: "stored" }
                : { key, variant: experiment.default, reason: "stored-retired" },
            );
          } else if (experiment.status === "stopped") {
            decisions.push({ key, variant: undefined, reason: "stopped" });
          } else if (!isTargeted(experiment.targeting, context)) {
            decisions.push({ key, variant: undefined, reason: "not-targeted" });
          } else {
            const result = yield* assign(experiment, context.pairId).pipe(
              Effect.provideService(Digest.Digest, digest),
            );
            if (result.exposed) {
              entering.push({
                pairId: context.pairId,
                experimentKey: key,
                variant: result.variant,
                assignedAt,
              });
            }
            decisions.push({
              key,
              variant: result.variant,
              reason: result.exposed ? "entered" : "outside-exposure",
            });
          }
        }
        if (!store || entering.length === 0) return decisions;

        // Both partners may enter at once: whatever was stored first wins for both.
        const saved = new Map(
          (yield* repository.saveMissing(context.pairId, entering)).map(
            ({ experimentKey, variant }) => [experimentKey, variant],
          ),
        );
        return decisions.map((decision) =>
          decision.reason === "entered"
            ? { ...decision, variant: saved.get(decision.key) ?? decision.variant }
            : decision,
        );
      });

      const listed = (decisions: ReadonlyArray<FlagDecision>): FlagsResponse["flags"] =>
        decisions.flatMap(({ key, variant }) => (variant === undefined ? [] : [{ key, variant }]));

      const flagsFor = Effect.fn("FlagsService.flagsFor")(function* (
        userId: UserId,
        caller: CallerContext,
      ): Effect.fn.Return<FlagsResponse, FlagsUnavailable> {
        const pairId = yield* pairing
          .findPair(userId)
          .pipe(Effect.mapError(() => new FlagsUnavailable({ reason: "directory-unavailable" })));
        if (Option.isNone(pairId)) return { flags: [] };
        return {
          flags: listed(
            yield* decide({ pairId: pairId.value, appVersion: caller.appVersion }, true),
          ),
        };
      });

      return FlagsService.of({
        flagsFor,
        assignPair: (pairId) => Effect.asVoid(decide({ pairId, appVersion: unknownClient }, true)),
        current,
        explain: (pairId, appVersion) => decide({ pairId, appVersion }, false),
      });
    }),
  );
}
