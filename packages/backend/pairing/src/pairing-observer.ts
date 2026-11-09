import { Context, Effect, Layer } from "effect";
import type { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";

/**
 * Side effects of pairing, never conditions: run after the commit, failures only logged.
 */
export class PairingObserver extends Context.Service<
  PairingObserver,
  {
    readonly invited: (userId: UserId) => Effect.Effect<void>;
    readonly paired: (
      pairId: PairId,
      members: ReadonlyArray<UserId>,
      joined: { readonly claimer: UserId; readonly at: EpochMillis },
    ) => Effect.Effect<void>;
    /** `members` are the two it had. */
    readonly unpaired: (pairId: PairId, members: ReadonlyArray<UserId>) => Effect.Effect<void>;
  }
>()("@billet/backend-pairing/PairingObserver") {
  /** Does nothing. For tests and for a Worker without the extras. */
  static readonly silent = Layer.succeed(PairingObserver, {
    invited: () => Effect.void,
    paired: () => Effect.void,
    unpaired: () => Effect.void,
  });
}
