import { Effect, Layer, Option, Schema } from "effect";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PaymentsConfig } from "@billet/backend-payments/payments-config";
import { PaymentsUnavailable } from "@billet/backend-payments/payments-error";
import { PaymentsSwitch } from "@billet/backend-payments/payments-switch";

const decodePairId = Schema.decodeUnknownOption(PairId);

/** The registry key of the `payments` flag (`payments.enabled` in docs/payments.md). */
const paymentsKey = "payments";

/**
 * Only `on` opens purchases; a demo room needs it on for everyone; the dev stage always sells.
 */
export const PaymentsSwitchLive: Layer.Layer<PaymentsSwitch, never, FlagsService | PaymentsConfig> =
  Layer.effect(
    PaymentsSwitch,
    Effect.gen(function* () {
      const flags = yield* FlagsService;
      if ((yield* PaymentsConfig).devTools) {
        return PaymentsSwitch.of({ enabledFor: () => Effect.succeed(true) });
      }
      return PaymentsSwitch.of({
        enabledFor: (owner, appVersion) => {
          // A demo room's ledger is `demo:<code>`: no pair, so no override or assignment. It is
          // on only once the flag is on for everyone: running, not killed, `on` as the default.
          if (owner.startsWith("demo:")) {
            return flags.current.pipe(
              Effect.map((experiments) =>
                experiments.some(
                  ({ key, killed, status, default: variant }) =>
                    key === paymentsKey && !killed && status === "running" && variant === "on",
                ),
              ),
              Effect.mapError(
                (cause) => new PaymentsUnavailable({ reason: "flags-unavailable", cause }),
              ),
            );
          }
          const pairId = decodePairId(owner);
          if (Option.isNone(pairId)) return Effect.succeed(false);
          return flags.explain(pairId.value, appVersion).pipe(
            Effect.map((decisions) =>
              decisions.some(({ key, variant }) => key === paymentsKey && variant === "on"),
            ),
            Effect.mapError(
              (cause) => new PaymentsUnavailable({ reason: "flags-unavailable", cause }),
            ),
          );
        },
      });
    }),
  );
