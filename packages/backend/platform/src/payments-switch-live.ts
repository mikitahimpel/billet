import { Effect, Layer, Option, Schema } from "effect";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PaymentsUnavailable } from "@billet/backend-payments/payments-error";
import { PaymentsSwitch } from "@billet/backend-payments/payments-switch";

const decodePairId = Schema.decodeUnknownOption(PairId);

/** The registry key of the `payments` flag (`payments.enabled` in docs/payments.md). */
const paymentsKey = "payments";

/**
 * `PaymentsSwitch` from the `payments` flag, as `FlagsService` would deliver it to the pair now.
 * Only the variant `on` opens the purchase routes: a draft without an override, a killed flag and a
 * pair outside its targeting are all off. A demo room has no pair, so it is on only when the flag
 * is on for everyone.
 */
export const PaymentsSwitchLive: Layer.Layer<PaymentsSwitch, never, FlagsService> = Layer.effect(
  PaymentsSwitch,
  Effect.gen(function* () {
    const flags = yield* FlagsService;
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
