import { Context, Effect, Layer } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";

/**
 * What else happens when a pair starts or ends: giving the new pair its experiment variants,
 * counting the funnel, ending an old pair's live sessions. These are side effects of pairing, never
 * conditions of it, so the service runs them after the change is committed and logs their failure.
 */
export class PairingObserver extends Context.Service<
  PairingObserver,
  {
    /** The user made a new invite code. */
    readonly invited: (userId: UserId) => Effect.Effect<void>;
    /** `members` now belong to `pairId`. */
    readonly paired: (pairId: PairId, members: ReadonlyArray<UserId>) => Effect.Effect<void>;
    /** `pairId` has no members any more. */
    readonly unpaired: (pairId: PairId) => Effect.Effect<void>;
  }
>()("@billet/backend-pairing/PairingObserver") {
  /** Does nothing. For tests and for a Worker without the extras. */
  static readonly silent = Layer.succeed(PairingObserver, {
    invited: () => Effect.void,
    paired: () => Effect.void,
    unpaired: () => Effect.void,
  });
}
