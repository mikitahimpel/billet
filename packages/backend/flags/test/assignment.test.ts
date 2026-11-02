import { Effect, Schema } from "effect";
import { Digest } from "effect/crypto";
import { describe, expect, it } from "vitest";
import { PairId } from "@billet/contracts-domain/pair-id";
import { assign, bucketCount, bucketOf } from "../src/assignment.ts";
import { defineExperiment } from "../src/experiments.ts";

const pair = Schema.decodeSync(PairId);
const run = <A>(effect: Effect.Effect<A, never, Digest.Digest>) =>
  Effect.runPromise(effect.pipe(Effect.provide(Digest.layerWebCrypto)));

const ids = Array.from({ length: 1_200 }, (_, i) => pair(`pair-${i}-${(i * 7919).toString(16)}`));

const twoWay = defineExperiment({
  key: "two-way",
  variants: { a: 1, b: 1 },
  default: "a",
  exposure: 100,
  killed: false,
});

describe("bucketOf", () => {
  it("is fixed by the seed and stays below the bucket count", async () => {
    const [one, again, other] = await run(
      Effect.all([bucketOf("seed"), bucketOf("seed"), bucketOf("seed-2")]),
    );
    expect(one).toBe(again);
    expect(one).not.toBe(other);
    expect(one).toBeGreaterThanOrEqual(0);
    expect(one).toBeLessThan(bucketCount);
  });

  it("is pinned to SHA-256, so the allocation cannot drift between servers or releases", async () => {
    // First 32 bits of the digest, modulo 10000, worked out with an independent SHA-256.
    expect(await run(bucketOf("pair-1:home-direction"))).toBe(2567);
    expect(await run(bucketOf("pair-1:home-direction:variant"))).toBe(6730);
    expect(await run(bucketOf("pair-2:home-direction"))).toBe(4970);
  });
});

describe("assign", () => {
  it("gives the same answer on every call, which is what makes both partners agree", async () => {
    const first = await run(Effect.all(ids.slice(0, 200).map((id) => assign(twoWay, id))));
    const second = await run(Effect.all(ids.slice(0, 200).map((id) => assign(twoWay, id))));
    expect(second).toEqual(first);
  });

  it("splits pairs by weight, within a few percent", async () => {
    const weighted = defineExperiment({
      key: "weighted",
      variants: { a: 1, b: 3 },
      default: "a",
      exposure: 100,
      killed: false,
    });
    const results = await run(Effect.all(ids.map((id) => assign(weighted, id))));
    const share = results.filter(({ variant }) => variant === "b").length / ids.length;
    expect(share).toBeGreaterThan(0.7);
    expect(share).toBeLessThan(0.8);
  });

  it("exposes about the given percent and gives everyone else the default", async () => {
    const partial = defineExperiment({
      key: "partial",
      variants: { a: 1, b: 1 },
      default: "a",
      exposure: 20,
      killed: false,
    });
    const results = await run(Effect.all(ids.map((id) => assign(partial, id))));
    const exposed = results.filter(({ exposed }) => exposed);
    expect(exposed.length / ids.length).toBeGreaterThan(0.16);
    expect(exposed.length / ids.length).toBeLessThan(0.24);
    expect(results.filter(({ exposed }) => !exposed).every(({ variant }) => variant === "a")).toBe(
      true,
    );
  });

  it("exposes nobody at 0% and everybody at 100%", async () => {
    const none = defineExperiment({
      key: "none",
      variants: { a: 1, b: 1 },
      default: "a",
      exposure: 0,
      killed: false,
    });
    expect(
      (await run(Effect.all(ids.slice(0, 200).map((id) => assign(none, id))))).some(
        (r) => r.exposed,
      ),
    ).toBe(false);
    expect(
      (await run(Effect.all(ids.slice(0, 200).map((id) => assign(twoWay, id))))).every(
        (r) => r.exposed,
      ),
    ).toBe(true);
  });

  it("keeps everyone already in when exposure is raised", async () => {
    const at = (exposure: number) =>
      defineExperiment({
        key: "ramp",
        variants: { a: 1, b: 1 },
        default: "a",
        exposure,
        killed: false,
      });
    const low = await run(Effect.all(ids.slice(0, 600).map((id) => assign(at(10), id))));
    const high = await run(Effect.all(ids.slice(0, 600).map((id) => assign(at(50), id))));
    low.forEach((before, i) => {
      if (before.exposed) expect(high[i]).toEqual(before);
    });
  });

  it("does not tie the variant to the exposure order", async () => {
    const partial = defineExperiment({
      key: "mix",
      variants: { a: 1, b: 1 },
      default: "a",
      exposure: 10,
      killed: false,
    });
    const exposed = (await run(Effect.all(ids.map((id) => assign(partial, id))))).filter(
      (r) => r.exposed,
    );
    const share = exposed.filter(({ variant }) => variant === "b").length / exposed.length;
    expect(share).toBeGreaterThan(0.3);
    expect(share).toBeLessThan(0.7);
  });

  it("assigns different experiments independently", async () => {
    const other = defineExperiment({
      key: "other",
      variants: { a: 1, b: 1 },
      default: "a",
      exposure: 100,
      killed: false,
    });
    const both = await run(
      Effect.all(ids.map((id) => Effect.all([assign(twoWay, id), assign(other, id)]))),
    );
    const sameShare = both.filter(([x, y]) => x.variant === y.variant).length / ids.length;
    expect(sameShare).toBeGreaterThan(0.44);
    expect(sameShare).toBeLessThan(0.56);
  });
});
