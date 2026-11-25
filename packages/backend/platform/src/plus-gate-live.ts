import { Effect, Layer } from "effect";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { declaresMinor } from "@billet/backend-onboarding/age-band";
import { OnboardingRepository } from "@billet/backend-onboarding/onboarding-repository";
import { PaymentsConfig } from "@billet/backend-payments/payments-config";
import { PaymentsUnavailable } from "@billet/backend-payments/payments-error";
import { PlusGate } from "@billet/backend-payments/plus-gate";

/** The registry key of the `plus` flag (docs/subscription.md). */
const plusKey = "plus";

/**
 * Only `on` opens Plus; the dev stage ignores the flag, as it does for `payments`. The age rule
 * holds on every stage: an account that answered 13 to 17 is never offered Plus.
 */
export const PlusGateLive: Layer.Layer<
  PlusGate,
  never,
  FlagsService | OnboardingRepository | PaymentsConfig
> = Layer.effect(
  PlusGate,
  Effect.gen(function* () {
    const flags = yield* FlagsService;
    const onboarding = yield* OnboardingRepository;
    const { devTools } = yield* PaymentsConfig;
    return PlusGate.of({
      closedFor: (userId, pairId, appVersion) =>
        Effect.gen(function* () {
          const answers = yield* onboarding
            .answersOf(userId)
            .pipe(
              Effect.mapError(
                (cause) => new PaymentsUnavailable({ reason: "onboarding-unavailable", cause }),
              ),
            );
          if (declaresMinor(answers)) return "declared-minor" as const;
          if (devTools) return undefined;
          const decisions = yield* flags
            .explain(pairId, appVersion)
            .pipe(
              Effect.mapError(
                (cause) => new PaymentsUnavailable({ reason: "flags-unavailable", cause }),
              ),
            );
          return decisions.some(({ key, variant }) => key === plusKey && variant === "on")
            ? undefined
            : ("flag-off" as const);
        }),
    });
  }),
);
