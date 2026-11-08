import { Context, Effect, Layer } from "effect";
import type { EpochMillis, UserId } from "@billet/contracts-domain/ids";
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
    /** `members` now belong to `pairId`: `claimer` claimed the invite at `at`. */
    readonly paired: (
      pairId: PairId,
      members: ReadonlyArray<UserId>,
      joined: { readonly claimer: UserId; readonly at: EpochMillis },
    ) => Effect.Effect<void>;
    /** `pairId` has no members any more; `members` are the two it had. */
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
