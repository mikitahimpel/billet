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

/** The directory rows of an account. Every storage failure is `AccountUnavailable`. */
export class AccountRepository extends Context.Service<
  AccountRepository,
  {
    /**
     * Every pair the user has been in that the directory still remembers: the current one and
     * those their counted events name. Their notes may still be in those rooms.
     */
    readonly pairsOf: (userId: UserId) => Effect.Effect<ReadonlyArray<PairId>, AccountUnavailable>;
    /**
     * In one atomic write: ends the user's pair, leaves the partner a notice, and deletes the user
     * with their sessions, Apple link, account key, devices, push tokens, invite and counted
     * events. Erasing a user who is already gone changes nothing.
     */
    readonly erase: (erasure: Erasure) => Effect.Effect<void, AccountUnavailable>;
  }
>()("@billet/backend-account/AccountRepository") {}
