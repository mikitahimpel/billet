import { Effect, Layer, Option, Schema } from "effect";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PaymentsUnavailable } from "@billet/backend-payments/payments-error";
import { PaymentsSwitch } from "@billet/backend-payments/payments-switch";

const decodePairId = Schema.decodeUnknownOption(PairId);

/**
 * `PaymentsSwitch` from the `payments` flag, as `FlagsService` would deliver it to the pair now.
 * Only the variant `on` opens the purchase routes: a draft without an override, a killed flag, a
 * pair outside its targeting and a demo room (no pair) are all off.
 */
export const PaymentsSwitchLive: Layer.Layer<PaymentsSwitch, never, FlagsService> = Layer.effect(
  PaymentsSwitch,
  Effect.gen(function* () {
    const flags = yield* FlagsService;
    return PaymentsSwitch.of({
      enabledFor: (owner, appVersion) => {
        // A demo room's ledger is `demo:<code>`: no pair, so no flags.
        const pairId = owner.startsWith("demo:") ? Option.none() : decodePairId(owner);
        if (Option.isNone(pairId)) return Effect.succeed(false);
        return flags.explain(pairId.value, appVersion).pipe(
          Effect.map((decisions) =>
            decisions.some(({ key, variant }) => key === "payments" && variant === "on"),
          ),
          Effect.mapError(
            (cause) => new PaymentsUnavailable({ reason: "flags-unavailable", cause }),
          ),
        );
      },
    });
  }),
);
