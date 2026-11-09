import { Context, type Effect, type Option } from "effect";
import type { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { AccountUnavailable } from "./account-error.ts";

/** The account to erase, and the partner to tell, if the user has one. */
export interface Erasure {
  readonly userId: UserId;
  readonly partner: Option.Option<UserId>;
  readonly at: EpochMillis;
}

export class AccountRepository extends Context.Service<
  AccountRepository,
  {
    /** The current pair and those their counted events name; their notes may still be there. */
    readonly pairsOf: (userId: UserId) => Effect.Effect<ReadonlyArray<PairId>, AccountUnavailable>;
    /**
     * One atomic write: ends the pair, notifies the partner, deletes the user and all their rows.
     */
    readonly erase: (erasure: Erasure) => Effect.Effect<void, AccountUnavailable>;
  }
>()("@billet/backend-account/AccountRepository") {}
