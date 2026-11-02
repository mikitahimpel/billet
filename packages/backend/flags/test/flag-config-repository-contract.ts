import { Effect, Exit, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { FlagConfigRepository } from "../src/flag-config-repository.ts";
import type { FlagConfig } from "../src/flag-config.ts";

const key = Schema.decodeSync(ExperimentKey);
const variant = Schema.decodeSync(VariantId);
const pair = Schema.decodeSync(PairId);

const config = (exposure: number): FlagConfig => ({
  description: "a test",
  weights: { [variant("a")]: 1, [variant("b")]: 1 },
  default: variant("a"),
  exposure,
  status: "running",
  killed: false,
  targeting: { minAppVersion: "1.2", pairIds: [pair("p1")] },
});

/**
 * The behaviour every `FlagConfigRepository` must have, run against each implementation so the
 * in-memory fake can't drift from D1. `make` must return an empty repository.
 */
export const describeFlagConfigRepositoryContract = (
  name: string,
  make: () => Promise<FlagConfigRepository["Service"]>,
) =>
  describe(`${name} (FlagConfigRepository contract)`, () => {
    const save = (
      repository: FlagConfigRepository["Service"],
      exposure: number,
      expectedVersion: number,
      by = "owner@example.com",
    ) =>
      Effect.runPromiseExit(
        repository.save({
          key: key("one"),
          config: config(exposure),
          expectedVersion,
          action: "edit",
          by,
          at: 1_000 + expectedVersion,
        }),
      );

    it("has nothing saved at first", async () => {
      const repository = await make();
      expect(await Effect.runPromise(repository.all)).toEqual([]);
      expect(await Effect.runPromise(repository.history(undefined, 10))).toEqual([]);
    });

    it("saves a configuration as version 1, then 2, and reads it back whole", async () => {
      const repository = await make();
      expect(Exit.isSuccess(await save(repository, 10, 0))).toBe(true);
      expect(Exit.isSuccess(await save(repository, 20, 1, "editor@example.com"))).toBe(true);
      expect(await Effect.runPromise(repository.all)).toEqual([
        {
          key: key("one"),
          config: config(20),
          version: 2,
          updatedAt: 1_001,
          updatedBy: "editor@example.com",
        },
      ]);
    });

    it("refuses a save from a version that is behind, and changes nothing", async () => {
      const repository = await make();
      await save(repository, 10, 0);
      const stale = await save(repository, 99, 0);
      expect(Exit.isFailure(stale)).toBe(true);
      expect(JSON.stringify(stale)).toContain("FlagConfigConflict");
      expect((await Effect.runPromise(repository.all))[0]?.config.exposure).toBe(10);
      expect(await Effect.runPromise(repository.history(undefined, 10))).toHaveLength(1);
    });

    it("keeps one history line per save, newest first, with who and before and after", async () => {
      const repository = await make();
      await save(repository, 10, 0, "first@example.com");
      await save(repository, 20, 1, "second@example.com");
      const history = await Effect.runPromise(repository.history(key("one"), 10));
      expect(history.map(({ by, action }) => [by, action])).toEqual([
        ["second@example.com", "edit"],
        ["first@example.com", "edit"],
      ]);
      expect(history[0]?.before).toEqual(config(10));
      expect(history[0]?.after).toEqual(config(20));
      expect(history[1]?.before).toBeNull();
      expect(await Effect.runPromise(repository.history(key("other"), 10))).toEqual([]);
      expect(await Effect.runPromise(repository.history(undefined, 1))).toHaveLength(1);
    });

    it("sets, replaces and clears a pair's override, and logs each", async () => {
      const repository = await make();
      const override = {
        pairId: pair("p1"),
        experimentKey: key("one"),
        variant: variant("b"),
        setAt: 5,
        setBy: "owner@example.com",
      };
      await Effect.runPromise(repository.setOverride(override));
      await Effect.runPromise(repository.setOverride({ ...override, variant: variant("a") }));
      expect(await Effect.runPromise(repository.overridesOf(pair("p1")))).toEqual([
        { ...override, variant: variant("a") },
      ]);
      expect(await Effect.runPromise(repository.overridesOf(pair("p2")))).toEqual([]);
      await Effect.runPromise(
        repository.clearOverride({
          pairId: pair("p1"),
          experimentKey: key("one"),
          by: "owner@example.com",
          at: 6,
        }),
      );
      expect(await Effect.runPromise(repository.overridesOf(pair("p1")))).toEqual([]);
      const history = await Effect.runPromise(repository.history(key("one"), 10));
      expect(history.map(({ action, pairId }) => [action, pairId])).toEqual([
        ["clear-override", "p1"],
        ["override", "p1"],
        ["override", "p1"],
      ]);
    });

    it("logs nothing when clearing an override that is not there", async () => {
      const repository = await make();
      await Effect.runPromise(
        repository.clearOverride({ pairId: pair("p1"), experimentKey: key("one"), by: "x", at: 1 }),
      );
      expect(await Effect.runPromise(repository.history(undefined, 10))).toEqual([]);
    });
  });
