import { Context, type Effect, type Option, Schema } from "effect";
import { TokenHash } from "@billet/backend-auth/auth-repository";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { ReportReason } from "@billet/contracts-http-api/safety";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { AlreadyPaired, InvalidInvite, PairingUnavailable } from "./pairing-error.ts";

/** What each stored table holds. A test in `platform` fails if a table's columns differ. */
export const StoredInvite = Schema.Struct({
  codeHash: TokenHash,
  ownerId: UserId,
  createdAt: EpochMillis,
  expiresAt: EpochMillis,
});
export type StoredInvite = typeof StoredInvite.Type;

export const StoredPairMember = Schema.Struct({
  userId: UserId,
  pairId: PairId,
  createdAt: EpochMillis,
});

export interface InviteClaim {
  readonly codeHash: TokenHash;
  readonly claimerId: UserId;
  /** A new id. It becomes the pair's only if this claim wins. */
  readonly pairId: PairId;
  readonly now: EpochMillis;
}

export const StoredBlock = Schema.Struct({
  blockerId: UserId,
  blockedId: UserId,
  createdAt: EpochMillis,
});

export const StoredPartnerReport = Schema.Struct({
  id: Schema.String,
  reporterId: UserId,
  reportedId: UserId,
  pairId: PairId,
  reason: ReportReason,
  details: Schema.NullOr(Schema.String),
  createdAt: EpochMillis,
});

export interface PartnerReport {
  readonly id: string;
  readonly reporter: UserId;
  readonly reported: UserId;
  readonly pairId: PairId;
  readonly reason: ReportReason;
  readonly details: string | undefined;
  readonly at: EpochMillis;
}

/**
 * Persistence for invites and the pair lookup. Each method is one atomic operation, every storage
 * failure is `PairingUnavailable`, and raw invite codes never reach it.
 * `test/pairing-repository-contract.ts` is the behaviour any implementation must pass.
 */
export class PairingRepository extends Context.Service<
  PairingRepository,
  {
    /**
     * Replaces the owner's invite, and removes every expired one. Fails, changing nothing for the
     * owner, if the owner has a partner.
     */
    readonly saveInvite: (
      invite: StoredInvite,
    ) => Effect.Effect<void, AlreadyPaired | PairingUnavailable>;
    /**
     * Pairs the claimer with the invite's owner and removes both users' invites, all or nothing, so
     * of any number of concurrent claims of one code, only one succeeds. The claimer's own code
     * is `InvalidInvite`. A failed claim leaves the invite as it was.
     */
    readonly claimInvite: (
      claim: InviteClaim,
    ) => Effect.Effect<void, InvalidInvite | AlreadyPaired | PairingUnavailable>;
    readonly findPair: (userId: UserId) => Effect.Effect<Option.Option<PairId>, PairingUnavailable>;
    /** When the pair formed: the moment its invite was claimed. None once it has ended. */
    readonly pairedAt: (
      pairId: PairId,
    ) => Effect.Effect<Option.Option<EpochMillis>, PairingUnavailable>;
    /** The users in a pair: none once it has ended. */
    readonly findMembers: (
      pairId: PairId,
    ) => Effect.Effect<ReadonlyArray<UserId>, PairingUnavailable>;
    /** Removes the lookup of both partners. Does nothing for a user without a partner. */
    readonly unpair: (userId: UserId) => Effect.Effect<void, PairingUnavailable>;
    /**
     * In one atomic write: records that `blocker` blocked `blocked` and removes the pair of
     * `blocker`. A claim of an invite between the two, either way round, is `InvalidInvite` from
     * then on. Safe to repeat.
     */
    readonly block: (block: {
      readonly blocker: UserId;
      readonly blocked: UserId;
      readonly at: EpochMillis;
    }) => Effect.Effect<void, PairingUnavailable>;
    /** Keeps a report for the team. The pair is untouched. */
    readonly saveReport: (report: PartnerReport) => Effect.Effect<void, PairingUnavailable>;
  }
>()("@billet/backend-pairing/PairingRepository") {}
