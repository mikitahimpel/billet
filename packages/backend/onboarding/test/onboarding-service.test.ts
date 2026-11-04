import { Effect, Exit, Layer, Option, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import { SaveOnboardingAnswerRequest } from "@billet/contracts-http-api/onboarding";
import { OnboardingCatalogue } from "../src/catalogue.ts";
import { InvalidAnswer } from "../src/onboarding-error.ts";
import { OnboardingRepository } from "../src/onboarding-repository.ts";
import { OnboardingService } from "../src/onboarding-service.ts";
import { makeInMemoryOnboardingRepository } from "./in-memory-onboarding-repository.ts";

const ana = Schema.decodeSync(UserId)("ana");
const request = (fields: Record<string, unknown>) =>
  Schema.decodeUnknownSync(SaveOnboardingAnswerRequest)({
    version: "2026-11-04",
    answeredAt: 1_000,
    ...fields,
  });

/** The `reason` of the `InvalidAnswer` an exit failed with, or undefined. */
const reasonOf = (exit: Exit.Exit<unknown, unknown>) =>
  Exit.isFailure(exit)
    ? Option.match(Exit.findErrorOption(exit), {
        onNone: () => undefined,
        onSome: (error) => (error instanceof InvalidAnswer ? error.reason : undefined),
      })
    : undefined;

const setup = () => {
  const memory = makeInMemoryOnboardingRepository();
  const layer = OnboardingService.layer.pipe(
    Layer.provide(
      Layer.mergeAll(
        OnboardingCatalogue.seed,
        Layer.succeed(OnboardingRepository, memory.repository),
      ),
    ),
  );
  const run = <A, E>(effect: Effect.Effect<A, E, OnboardingService>, now = 10_000) =>
    Effect.runPromise(
      Effect.exit(
        Effect.gen(function* () {
          yield* TestClock.setTime(now);
          return yield* effect;
        }).pipe(Effect.provide(layer), Effect.provide(TestClock.layer())),
      ),
    );
  return { memory, run };
};

describe("OnboardingService", () => {
  it("stores an answer and a skip that fit the catalogue", async () => {
    const { memory, run } = setup();
    const save = (fields: Record<string, unknown>) =>
      OnboardingService.use((service) => service.save(ana, request(fields)));
    expect(
      Exit.isSuccess(
        await run(save({ stepId: "age", answer: { _tag: "Single", option: "age-25-34" } })),
      ),
    ).toBe(true);
    expect(Exit.isSuccess(await run(save({ stepId: "name", answer: { _tag: "Skipped" } })))).toBe(
      true,
    );
    expect([...memory.rows.values()].map((row) => [row.stepId, row.answer._tag])).toEqual([
      ["age", "Single"],
      ["name", "Skipped"],
    ]);
  });

  it("refuses an unknown step and an answer that doesn't fit", async () => {
    const { memory, run } = setup();
    const save = (fields: Record<string, unknown>) =>
      OnboardingService.use((service) => service.save(ana, request(fields)));
    expect(reasonOf(await run(save({ stepId: "zodiac", answer: { _tag: "Skipped" } })))).toBe(
      "unknown-step",
    );
    expect(
      reasonOf(await run(save({ stepId: "age", answer: { _tag: "Single", option: "age-99" } }))),
    ).toBe("answer-mismatch");
    expect(
      reasonOf(await run(save({ stepId: "name", answer: { _tag: "Text", text: "x".repeat(21) } }))),
    ).toBe("answer-mismatch");
    expect(memory.rows.size).toBe(0);
  });

  it("takes an answeredAt from a phone clock running ahead as the server's now", async () => {
    const { memory, run } = setup();
    await run(
      OnboardingService.use((service) =>
        service.save(
          ana,
          request({ stepId: "age", answer: { _tag: "Skipped" }, answeredAt: 99_999 }),
        ),
      ),
      5_000,
    );
    expect([...memory.rows.values()][0]?.answeredAt).toBe(5_000);
  });
});
