import { Effect, Layer, Schema } from "effect";
import { Digest } from "effect/crypto";
import { describe, expect, it } from "vitest";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId as PairIdSchema, type PairId } from "@billet/contracts-domain/pair-id";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import { assign } from "../src/assignment.ts";
import { defineExperiment, defineExperiments, Experiments } from "../src/experiments.ts";
import { FlagsUnavailable } from "../src/flags-error.ts";
import { FlagsRepository } from "../src/flags-repository.ts";
import { FlagsService } from "../src/flags-service.ts";
import { FlagConfigRepository } from "../src/flag-config-repository.ts";
import { configOf } from "../src/flag-config.ts";
import { makeInMemoryFlagConfigRepository } from "./in-memory-flag-config-repository.ts";
import { makeInMemoryFlagsRepository } from "./in-memory-flags-repository.ts";

const user = Schema.decodeSync(UserId);
const ana = user("user-a");
const ben = user("user-b");
const cal = user("user-c");

const caller = { appVersion: "1.3.0+20" };

const spec = (key: string, overrides: Partial<Parameters<typeof defineExperiment>[0]> = {}) => ({
  key,
  variants: { control: 1, bold: 1 },
  default: "control",
  exposure: 100,
  killed: false,
  ...overrides,
});

const setup = (specs: ReadonlyArray<Parameters<typeof defineExperiment>[0]>) => {
  const pairs = makeInMemoryPairingRepository();
  const flags = makeInMemoryFlagsRepository();
  const configs = makeInMemoryFlagConfigRepository();
  const build = (
    experiments: ReadonlyArray<ReturnType<typeof defineExperiment>>,
    repository = flags.repository,
  ) =>
    FlagsService.layer.pipe(
      Layer.provide(
        Layer.mergeAll(
          Layer.succeed(PairingRepository, pairs.repository),
          Layer.succeed(FlagsRepository, repository),
          Layer.succeed(FlagConfigRepository, configs.repository),
          Experiments.with(experiments),
          Digest.layerWebCrypto,
        ),
      ),
    );
  const run = <A, E>(
    use: (service: FlagsService["Service"]) => Effect.Effect<A, E>,
    experiments = defineExperiments(specs),
    repository = flags.repository,
  ) =>
    Effect.runPromise(
      Effect.gen(function* () {
        return yield* use(yield* FlagsService);
      }).pipe(Effect.provide(build(experiments, repository))),
    );
  const pairUp = async (first: typeof ana, second: typeof ana, pairId: string) => {
    const codeHash = `hash-${first}`;
    await Effect.runPromise(
      pairs.repository.saveInvite({ codeHash, ownerId: first, createdAt: 1, expiresAt: 10 }),
    );
    await Effect.runPromise(
      pairs.repository.claimInvite({
        codeHash,
        claimerId: second,
        pairId: pairId as PairId,
        now: 2,
      }),
    );
    return pairId as PairId;
  };
  return { pairs, flags, configs, run, pairUp };
};

describe("FlagsService", () => {
  it("gives both partners the same variants", async () => {
    const { run, pairUp } = setup([
      spec("one"),
      spec("two", { variants: { x: 1, y: 2, z: 1 }, default: "x" }),
    ]);
    await pairUp(ana, ben, "pair-1");
    const [forAna, forBen] = await run((service) =>
      Effect.all([service.flagsFor(ana, caller), service.flagsFor(ben, caller)]),
    );
    expect(forAna).toEqual(forBen);
    expect(forAna.flags.map(({ key }) => key)).toEqual(["one", "two"]);
  });

  it("gives the variant that hash(pairId + experimentKey) picks", async () => {
    const experiment = defineExperiment(spec("one"));
    const { run, pairUp } = setup([spec("one")]);
    const pairId = await pairUp(ana, ben, "pair-7");
    const expected = await Effect.runPromise(
      assign(experiment, pairId).pipe(Effect.provide(Digest.layerWebCrypto)),
    );
    expect((await run((service) => service.flagsFor(ana, caller))).flags).toEqual([
      { key: "one", variant: expected.variant },
    ]);
  });

  it("lists nothing for a user without a partner", async () => {
    const { run } = setup([spec("one")]);
    expect(await run((service) => service.flagsFor(cal, caller))).toEqual({ flags: [] });
  });

  it("does not deliver an experiment that is killed, so clients fall back to their defaults", async () => {
    const { run, pairUp } = setup([spec("live"), spec("dead", { killed: true })]);
    await pairUp(ana, ben, "pair-1");
    const keys = (await run((service) => service.flagsFor(ana, caller))).flags.map(
      ({ key }) => key,
    );
    expect(keys).toEqual(["live"]);
  });

  it("stores nothing for a killed experiment, and nothing when no experiment is running", async () => {
    const { run, pairUp, flags } = setup([spec("dead", { killed: true })]);
    await pairUp(ana, ben, "pair-1");
    await run((service) => service.flagsFor(ana, caller));
    expect(flags.rows.size).toBe(0);
  });

  it("takes an experiment back after the switch-off is lifted, with the same variant as before", async () => {
    const { run, pairUp } = setup([]);
    await pairUp(ana, ben, "pair-1");
    const running = defineExperiments([spec("one")]);
    const killed = defineExperiments([spec("one", { killed: true })]);
    const before = await run((service) => service.flagsFor(ana, caller), running);
    expect((await run((service) => service.flagsFor(ana, caller), killed)).flags).toEqual([]);
    expect(await run((service) => service.flagsFor(ana, caller), running)).toEqual(before);
  });

  it("freezes a pair's variant: changing the weights later moves nobody who is in", async () => {
    const { run, pairUp } = setup([]);
    await pairUp(ana, ben, "pair-1");
    const first = defineExperiments([spec("one")]);
    const reweighted = defineExperiments([spec("one", { variants: { control: 1, bold: 99 } })]);
    const before = await run((service) => service.flagsFor(ana, caller), first);
    const during = await run((service) => service.flagsFor(ana, caller), reweighted);
    expect(during).toEqual(before);
  });

  it("gives a pair whose stored variant was retired the default, without a new roll", async () => {
    const { run, pairUp, flags } = setup([]);
    const pairId = await pairUp(ana, ben, "pair-1");
    const key = Schema.decodeSync(ExperimentKey)("one");
    await Effect.runPromise(
      flags.repository.saveMissing(pairId, [
        {
          pairId,
          experimentKey: key,
          variant: Schema.decodeSync(VariantId)("retired"),
          assignedAt: 1,
        },
      ]),
    );
    const delivered = await run(
      (service) => service.flagsFor(ana, caller),
      defineExperiments([spec("one")]),
    );
    expect(delivered.flags).toEqual([{ key: "one", variant: "control" }]);
    expect(flags.rows.get(`${pairId}/one`)?.variant).toBe("retired");
  });

  it("brings pairs in when exposure is raised and keeps those already in", async () => {
    const { run, pairUp, flags } = setup([]);
    const pairs = await Promise.all(
      Array.from({ length: 60 }, (_, i) => pairUp(user(`a-${i}`), user(`b-${i}`), `pair-${i}`)),
    );
    const at = (exposure: number) => defineExperiments([spec("ramp", { exposure })]);
    const read = (exposure: number) =>
      Promise.all(
        pairs.map((_, i) =>
          run((service) => service.flagsFor(user(`a-${i}`), caller), at(exposure)),
        ),
      );
    await read(20);
    const enteredAt20 = [...flags.rows.values()].map(({ pairId, variant }) => [pairId, variant]);
    await read(80);
    const enteredAt80 = new Map(
      [...flags.rows.values()].map(({ pairId, variant }) => [pairId, variant]),
    );
    expect(enteredAt20.length).toBeGreaterThan(0);
    expect(enteredAt80.size).toBeGreaterThan(enteredAt20.length);
    for (const [pairId, variant] of enteredAt20)
      expect(enteredAt80.get(pairId as PairId)).toBe(variant);
  });

  it("assignPair stores the same thing that reading would, and a second call changes nothing", async () => {
    const { run, pairUp, flags } = setup([spec("one"), spec("two")]);
    const pairId = await pairUp(ana, ben, "pair-1");
    await run((service) => service.assignPair(pairId));
    const stored = [...flags.rows.values()];
    await run((service) => service.assignPair(pairId));
    expect([...flags.rows.values()]).toEqual(stored);
    const delivered = (await run((service) => service.flagsFor(ben, caller))).flags;
    expect(delivered).toEqual(
      stored.map(({ experimentKey, variant }) => ({ key: experimentKey, variant })),
    );
  });

  it("answers FlagsUnavailable, with a fixed reason, when storage fails", async () => {
    const { run, pairUp } = setup([spec("one")]);
    await pairUp(ana, ben, "pair-1");
    const broken = {
      find: () => Effect.fail(new FlagsUnavailable({ reason: "directory-unavailable" })),
      saveMissing: () => Effect.fail(new FlagsUnavailable({ reason: "directory-unavailable" })),
    };
    const failure = await run(
      (service) => service.flagsFor(ana, caller).pipe(Effect.flip),
      defineExperiments([spec("one")]),
      broken,
    );
    expect(failure).toEqual(new FlagsUnavailable({ reason: "directory-unavailable" }));
  });

  describe("configured without a deploy", () => {
    const key = Schema.decodeSync(ExperimentKey);
    const variant = Schema.decodeSync(VariantId);
    const pairOf = Schema.decodeSync(PairIdSchema);
    const edit = (
      configs: ReturnType<typeof makeInMemoryFlagConfigRepository>,
      base: Parameters<typeof defineExperiment>[0],
      change: Partial<ReturnType<typeof configOf>>,
    ) => {
      const version = configs.configs.get(base.key)?.version ?? 0;
      return Effect.runPromise(
        configs.repository.save({
          key: key(base.key),
          config: { ...configOf(defineExperiment(base)), ...change },
          expectedVersion: version,
          action: "edit",
          by: "owner@example.com",
          at: 1,
        }),
      );
    };
    const override = (
      configs: ReturnType<typeof makeInMemoryFlagConfigRepository>,
      pairId: PairId,
      experiment: string,
      chosen: string,
    ) =>
      Effect.runPromise(
        configs.repository.setOverride({
          pairId,
          experimentKey: key(experiment),
          variant: variant(chosen),
          setAt: 1,
          setBy: "owner@example.com",
        }),
      );

    it("applies a saved configuration in place of the registry's", async () => {
      const base = spec("one");
      const { run, pairUp, configs } = setup([base]);
      await pairUp(ana, ben, "pair-1");
      await edit(configs, base, { weights: { [variant("control")]: 0, [variant("bold")]: 1 } });
      expect((await run((service) => service.flagsFor(ana, caller))).flags).toEqual([
        { key: "one", variant: "bold" },
      ]);
    });

    it("ignores a saved configuration that names a variant the registry lacks", async () => {
      const base = spec("one", { variants: { control: 1, bold: 0 } });
      const { run, pairUp, configs } = setup([base]);
      await pairUp(ana, ben, "pair-1");
      configs.configs.set("one", {
        key: key("one"),
        config: {
          ...configOf(defineExperiment(base)),
          weights: { [variant("unbuilt")]: 1, [variant("control")]: 0, [variant("bold")]: 0 },
        },
        version: 1,
        updatedAt: 1,
        updatedBy: "x",
      });
      expect((await run((service) => service.flagsFor(ana, caller))).flags).toEqual([
        { key: "one", variant: "control" },
      ]);
    });

    it("delivers a draft to nobody but a pair with an override", async () => {
      const { run, pairUp, configs, flags } = setup([spec("one", { status: "draft" })]);
      const tester = await pairUp(ana, ben, "pair-1");
      await pairUp(cal, user("user-d"), "pair-2");
      await override(configs, tester, "one", "bold");
      expect((await run((service) => service.flagsFor(ana, caller))).flags).toEqual([
        { key: "one", variant: "bold" },
      ]);
      expect((await run((service) => service.flagsFor(cal, caller))).flags).toEqual([]);
      expect(flags.rows.size).toBe(0);
    });

    it("lets the kill switch beat an override", async () => {
      const { run, pairUp, configs } = setup([spec("one", { killed: true })]);
      const pairId = await pairUp(ana, ben, "pair-1");
      await override(configs, pairId, "one", "bold");
      expect((await run((service) => service.flagsFor(ana, caller))).flags).toEqual([]);
    });

    it("ignores an override naming a variant the entry does not have", async () => {
      const { run, pairUp, configs } = setup([spec("one", { variants: { control: 1, bold: 0 } })]);
      const pairId = await pairUp(ana, ben, "pair-1");
      await override(configs, pairId, "one", "gone");
      expect((await run((service) => service.flagsFor(ana, caller))).flags).toEqual([
        { key: "one", variant: "control" },
      ]);
    });

    it("takes nobody new into a stopped experiment, and keeps those already in", async () => {
      const base = spec("one");
      const { run, pairUp, configs } = setup([base]);
      await pairUp(ana, ben, "pair-1");
      const before = await run((service) => service.flagsFor(ana, caller));
      await edit(configs, base, { status: "stopped" });
      await pairUp(cal, user("user-d"), "pair-2");
      expect(await run((service) => service.flagsFor(ana, caller))).toEqual(before);
      expect((await run((service) => service.flagsFor(cal, caller))).flags).toEqual([]);
    });

    it.each([
      ["below the minimum", { minAppVersion: "1.4" }, false],
      ["at the minimum, any build", { minAppVersion: "1.3" }, true],
      ["an earlier build of the minimum", { minAppVersion: "1.3.0+21" }, false],
      ["above the maximum", { maxAppVersion: "1.2.9" }, false],
      ["inside both bounds", { minAppVersion: "1.0", maxAppVersion: "2" }, true],
    ])("targets by app version: %s", async (_, targeting, listed) => {
      const { run, pairUp, flags } = setup([spec("one", { targeting })]);
      await pairUp(ana, ben, "pair-1");
      const delivered = (await run((service) => service.flagsFor(ana, caller))).flags;
      expect(delivered.length === 1).toBe(listed);
      expect(flags.rows.size === 1).toBe(listed);
    });

    it("leaves a build that sent no version out of a version-targeted experiment", async () => {
      const { run, pairUp } = setup([spec("one", { targeting: { minAppVersion: "1.0" } })]);
      await pairUp(ana, ben, "pair-1");
      const delivered = await run((service) => service.flagsFor(ana, { appVersion: "unknown" }));
      expect(delivered.flags).toEqual([]);
    });

    it("targets a list of pairs", async () => {
      const { run, pairUp } = setup([spec("one", { targeting: { pairIds: [pairOf("pair-2")] } })]);
      await pairUp(ana, ben, "pair-1");
      await pairUp(cal, user("user-d"), "pair-2");
      expect((await run((service) => service.flagsFor(ana, caller))).flags).toEqual([]);
      expect((await run((service) => service.flagsFor(cal, caller))).flags).toHaveLength(1);
    });

    it("leaves pairs whose age band is not known out of a band-targeted experiment", async () => {
      const { run, pairUp } = setup([spec("one", { targeting: { ageBands: ["18+"] } })]);
      await pairUp(ana, ben, "pair-1");
      expect((await run((service) => service.flagsFor(ana, caller))).flags).toEqual([]);
    });

    it("keeps a stored pair in when the targeting later leaves it out", async () => {
      const base = spec("one");
      const { run, pairUp, configs } = setup([base]);
      await pairUp(ana, ben, "pair-1");
      const before = await run((service) => service.flagsFor(ana, caller));
      await edit(configs, base, { targeting: { minAppVersion: "9" } });
      expect(await run((service) => service.flagsFor(ana, caller))).toEqual(before);
    });

    it("explains every decision without storing anything", async () => {
      const { run, pairUp, configs, flags } = setup([
        spec("dead", { killed: true }),
        spec("draft", { status: "draft" }),
        spec("forced", { status: "draft" }),
        spec("old", { targeting: { minAppVersion: "9" } }),
        spec("open"),
        spec("none", { exposure: 0 }),
      ]);
      const pairId = await pairUp(ana, ben, "pair-1");
      await override(configs, pairId, "forced", "bold");
      const decisions = await run((service) => service.explain(pairId, "1.0"));
      expect(decisions.map(({ key, reason }) => [key, reason])).toEqual([
        ["dead", "killed"],
        ["draft", "draft"],
        ["forced", "override"],
        ["old", "not-targeted"],
        ["open", "entered"],
        ["none", "outside-exposure"],
      ]);
      expect(decisions.find(({ key }) => key === "none")?.variant).toBe("control");
      expect(flags.rows.size).toBe(0);
    });
  });
});
