import { Context, Effect, Layer } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { PaymentsUnavailable } from "./payments-error.ts";

/** Why Plus is closed to a caller. Each reads as a 404, like a route that does not exist. */
export type PlusClosed = "flag-off" | "declared-minor";

/**
 * Whether a caller may see and buy Ourio Plus: the `plus` flag is on for their pair (always on
 * the dev stage), and they did not answer 13 to 17 in onboarding. `platform` answers it from
 * `FlagsService` and the onboarding answers; tests use `open` and `closed`.
 */
export class PlusGate extends Context.Service<
  PlusGate,
  {
    readonly closedFor: (
      userId: UserId,
      pairId: PairId,
      appVersion: string,
    ) => Effect.Effect<PlusClosed | undefined, PaymentsUnavailable>;
  }
>()("@billet/backend-payments/PlusGate") {
  static readonly open = Layer.succeed(PlusGate, { closedFor: () => Effect.succeed(undefined) });
  static readonly closed = (reason: PlusClosed) =>
    Layer.succeed(PlusGate, { closedFor: () => Effect.succeed(reason) });
}
