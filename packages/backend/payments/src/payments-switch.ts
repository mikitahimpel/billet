import { Context, Effect, Layer } from "effect";
import type { PaymentsUnavailable } from "./payments-error.ts";
import type { CoinOwner } from "./payments-repository.ts";

/** The `payments` flag, off until the owner turns it on and always on on the dev stage.
 * `platform` reads it from `FlagsService`; tests use `on` and `off`. */
export class PaymentsSwitch extends Context.Service<
  PaymentsSwitch,
  {
    /** `appVersion` is the caller's build, for a flag targeted by app version. */
    readonly enabledFor: (
      owner: CoinOwner,
      appVersion: string,
    ) => Effect.Effect<boolean, PaymentsUnavailable>;
  }
>()("@billet/backend-payments/PaymentsSwitch") {
  static readonly on = Layer.succeed(PaymentsSwitch, { enabledFor: () => Effect.succeed(true) });
  static readonly off = Layer.succeed(PaymentsSwitch, { enabledFor: () => Effect.succeed(false) });
}
