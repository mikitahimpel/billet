import { Context, Effect, Layer } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";

/**
 * What else happens when pairing succeeds: giving the new pair its experiment variants and
 * counting the funnel. These are side effects of pairing, never conditions of it, so the service
 * runs them after the pairing is committed and ignores their failure.
 */
export class PairingObserver extends Context.Service<
  PairingObserver,
  {
    /** The user made a new invite code. */
    readonly invited: (userId: UserId) => Effect.Effect<void>;
    /** `members` now belong to `pairId`. */
    readonly paired: (pairId: PairId, members: ReadonlyArray<UserId>) => Effect.Effect<void>;
  }
>()("@billet/backend-pairing/PairingObserver") {
  /** Does nothing. For tests and for a Worker without the extras. */
  static readonly silent = Layer.succeed(PairingObserver, {
    invited: () => Effect.void,
    paired: () => Effect.void,
  });
}
