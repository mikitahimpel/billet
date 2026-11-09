import { Context, type Effect, type Option, Schema } from "effect";
import { TokenHash } from "@billet/backend-auth/auth-repository";
import { EpochMillis, NoteId, UserId } from "@billet/contracts-domain/ids";
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

/** Purchases a user keeps when their pair ends: their coins, inks and room pieces. */
export interface KeptPurchases {
  readonly coins: number;
  readonly inks: ReadonlyArray<string>;
  readonly items: ReadonlyArray<string>;
}

export const StoredKeptWallet = Schema.Struct({
  userId: UserId,
  coins: Schema.Int,
});

export const StoredKeptItem = Schema.Struct({
  userId: UserId,
  kind: Schema.Literals(["ink", "item"]),
  itemId: Schema.String,
});

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
  noteId: Schema.NullOr(NoteId),
  createdAt: EpochMillis,
});

export interface PartnerReport {
  readonly id: string;
  readonly reporter: UserId;
  readonly reported: UserId;
  readonly pairId: PairId;
  readonly reason: ReportReason;
  readonly details: string | undefined;
  /** The note or photo the report is about, when it is about one. */
  readonly noteId: NoteId | undefined;
  readonly at: EpochMillis;
}

/**
 * Each method is atomic; raw invite codes never reach it (`test/pairing-repository-contract.ts`).
 */
export class PairingRepository extends Context.Service<
  PairingRepository,
  {
    /** Also removes every expired invite. Fails, changing nothing, if the owner has a partner. */
    readonly saveInvite: (
      invite: StoredInvite,
    ) => Effect.Effect<void, AlreadyPaired | PairingUnavailable>;
    /**
     * All or nothing: of concurrent claims of one code only one wins. Own code is `InvalidInvite`.
     */
    readonly claimInvite: (
      claim: InviteClaim,
    ) => Effect.Effect<void, InvalidInvite | AlreadyPaired | PairingUnavailable>;
    readonly findPair: (userId: UserId) => Effect.Effect<Option.Option<PairId>, PairingUnavailable>;
    /** When the pair formed: the moment its invite was claimed. None once it has ended. */
    readonly pairedAt: (
      pairId: PairId,
    ) => Effect.Effect<Option.Option<EpochMillis>, PairingUnavailable>;
    /** None once the pair has ended. */
    readonly findMembers: (
      pairId: PairId,
    ) => Effect.Effect<ReadonlyArray<UserId>, PairingUnavailable>;
    /** Removes the lookup of both partners. Does nothing for a user without a partner. */
    readonly unpair: (userId: UserId) => Effect.Effect<void, PairingUnavailable>;
    /**
     * Atomic with the unpair; later invite claims between the two are `InvalidInvite`. Idempotent.
     */
    readonly block: (block: {
      readonly blocker: UserId;
      readonly blocked: UserId;
      readonly at: EpochMillis;
    }) => Effect.Effect<void, PairingUnavailable>;
    /** Adds to what `userId` keeps. Safe to repeat for the items, not for the coins. */
    readonly keep: (userId: UserId, kept: KeptPurchases) => Effect.Effect<void, PairingUnavailable>;
    readonly kept: (userId: UserId) => Effect.Effect<KeptPurchases, PairingUnavailable>;
    /** Forgets what `userId` keeps, once the new pair's room has it. */
    readonly clearKept: (userId: UserId) => Effect.Effect<void, PairingUnavailable>;
    /** Keeps a report for the team. The pair is untouched. */
    readonly saveReport: (report: PartnerReport) => Effect.Effect<void, PairingUnavailable>;
  }
>()("@billet/backend-pairing/PairingRepository") {}
