import { Effect, Layer, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { OnboardingRepository } from "@billet/backend-onboarding/onboarding-repository";
import { StoredOnboardingAnswer } from "@billet/backend-onboarding/onboarding-repository";
import { PaymentsConfig, settingsForStage } from "@billet/backend-payments/payments-config";
import { PlusGate } from "@billet/backend-payments/plus-gate";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PlusGateLive } from "../src/plus-gate-live.ts";

const user = Schema.decodeSync(UserId);
const pairId = Schema.decodeSync(PairId)("pair-1");

const answers = (option: string | undefined) =>
  Layer.succeed(OnboardingRepository, {
    save: () => Effect.die("unused"),
    answersOf: (userId) =>
      Effect.succeed(
        option === undefined
          ? []
          : [
              Schema.decodeUnknownSync(StoredOnboardingAnswer)({
                userId,
                stepId: "age",
                version: "2026-11-04",
                answer: { _tag: "Single", option },
                answeredAt: 1,
              }),
            ],
      ),
  });

const flags = (variant: string | undefined) =>
  Layer.succeed(FlagsService, {
    flagsFor: () => Effect.die("unused"),
    assignPair: () => Effect.die("unused"),
    current: Effect.die("unused"),
    explain: () =>
      Effect.succeed([
        {
          key: Schema.decodeSync(ExperimentKey)("plus"),
          variant: variant === undefined ? undefined : Schema.decodeSync(VariantId)(variant),
          reason: "entered" as const,
        },
      ]),
  });

const closedFor = (stage: string, variant: string | undefined, option: string | undefined) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const gate = yield* PlusGate;
      return yield* gate.closedFor(user("leo"), pairId, "1.2+70");
    }).pipe(
      Effect.provide(
        PlusGateLive.pipe(
          Layer.provide(
            Layer.mergeAll(
              flags(variant),
              answers(option),
              PaymentsConfig.with(settingsForStage(stage, [])),
            ),
          ),
        ),
      ),
    ),
  );

describe("PlusGateLive", () => {
  it("opens only where the plus flag is on, and always on dev", async () => {
    expect(await closedFor("prod", "on", "age-25-34")).toBeUndefined();
    expect(await closedFor("prod", "off", "age-25-34")).toBe("flag-off");
    expect(await closedFor("prod", undefined, undefined)).toBe("flag-off");
    expect(await closedFor("dev", "off", undefined)).toBeUndefined();
  });

  it("closes for an account that said 13 to 17, on every stage", async () => {
    expect(await closedFor("prod", "on", "age-13-17")).toBe("declared-minor");
    expect(await closedFor("dev", "on", "age-13-17")).toBe("declared-minor");
  });
});
