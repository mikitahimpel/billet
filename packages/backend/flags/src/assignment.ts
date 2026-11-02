import { Effect } from "effect";
import { Digest } from "effect/crypto";
import type { VariantId } from "@billet/contracts-domain/flags";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { Experiment } from "./experiments.ts";

/** Pairs fall into one of this many buckets, so exposure and weights have 0.01% resolution. */
export const bucketCount = 10_000;

const encoder = new TextEncoder();

/** A number from 0 up to `bucketCount`, fixed by the seed. SHA-256 spreads similar seeds evenly. */
export const bucketOf = (seed: string): Effect.Effect<number, never, Digest.Digest> =>
  Effect.gen(function* () {
    const digest = yield* Digest.Digest;
    const hex = yield* digest.digestHex(Digest.sha256, encoder.encode(seed)).pipe(Effect.orDie);
    return Number.parseInt(hex.slice(0, 8), 16) % bucketCount;
  });

export interface Assignment {
  readonly variant: VariantId;
  /** False when the pair is outside the experiment: it gets the default and is not analysed. */
  readonly exposed: boolean;
}

/**
 * The variant of `pairId` in `experiment`, from `hash(pairId + experimentKey)`. It depends on
 * nothing else, so every call (either partner, any server, any time) gives the same answer for the
 * same weights. Exposure and variant use two separate hashes, so being early in the exposure
 * order says nothing about which variant a pair gets.
 */
export const assign = (
  experiment: Experiment,
  pairId: PairId,
): Effect.Effect<Assignment, never, Digest.Digest> =>
  Effect.gen(function* () {
    const exposure = yield* bucketOf(`${pairId}:${experiment.key}`);
    if (exposure >= experiment.exposure * 100) {
      return { variant: experiment.default, exposed: false };
    }
    const total = experiment.variants.reduce((sum, { weight }) => sum + weight, 0);
    const pick = Math.floor(
      ((yield* bucketOf(`${pairId}:${experiment.key}:variant`)) * total) / bucketCount,
    );
    let upTo = 0;
    for (const { id, weight } of experiment.variants) {
      upTo += weight;
      if (pick < upTo) return { variant: id, exposed: true };
    }
    return { variant: experiment.default, exposed: true };
  });
