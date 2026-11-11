import { Effect, Schema } from "effect";
import { CatEntry, CatProfile, CatTemper } from "@billet/contracts-domain/cat";
import { LocalDay } from "@billet/contracts-domain/coins";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import { MoodCheckIn } from "@billet/contracts-domain/mood";
import { LoveStreak } from "@billet/contracts-domain/streak";
import { Note } from "@billet/contracts-domain/note";
import { PairId } from "@billet/contracts-domain/pair-id";
import { IdempotencyKey } from "@billet/contracts-domain/ids";
import { CollectionId, Placement, RoomItemId } from "@billet/contracts-domain/shop";
import { PresenceState } from "@billet/contracts-realtime/client-message";

/** A partner and their presence, kept together so presence cannot exist for a stranger. */
export const Member = Schema.Struct({ user: UserId, presence: PresenceState });
export type Member = typeof Member.Type;

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** A count stored before it existed reads as 0. */
const NewCount = Count.pipe(Schema.withDecodingDefaultKey(Effect.succeed(0)));

/** Two different people: a room cannot be built around one user twice. */
const Couple = Schema.Tuple([Member, Member]).check(
  Schema.makeFilter(([first, second]) =>
    first.user === second.user ? "a room needs two different members" : true,
  ),
);

/** The couple's cat without its unbounded journal, which stays in the store. */
export const RoomCat = Schema.Struct({
  profile: CatProfile,
  temper: CatTemper,
  lastSeq: Count,
  /** When the last entry was stored, absent before the first. The temper reads the gap. */
  lastAt: Schema.optionalKey(EpochMillis),
});
export type RoomCat = typeof RoomCat.Type;

/** The pair's coins: the balance, and what was earned on `day` against each daily cap. */
export const RoomWallet = Schema.Struct({
  balance: Count,
  /** The local day the earned counts are for, absent before the first coin is earned. */
  day: Schema.optionalKey(LocalDay),
  care: Count,
  notes: Count,
  games: Count,
  lists: NewCount,
});
export type RoomWallet = typeof RoomWallet.Type;

export const emptyWallet: RoomWallet = { balance: 0, care: 0, notes: 0, games: 0, lists: 0 };

/**
 * The room without its unbounded notes. `inks` and `items` leave out the free ink and starters.
 */
export const RoomState = Schema.TaggedUnion({
  /** A new object, not given to a couple yet. */
  Vacant: {},
  Active: {
    pairId: PairId,
    members: Couple,
    lastSeq: Count,
    streak: LoveStreak,
    /** Absent until one of the couple adopts the cat. */
    cat: Schema.optionalKey(RoomCat),
    inks: Schema.Array(InkId),
    items: Schema.Array(RoomItemId),
    /** Pieces the pair wishes for, in the order they were wished. */
    wishlist: Schema.Array(RoomItemId),
    bonuses: Schema.Array(CollectionId).pipe(Schema.withDecodingDefaultKey(Effect.succeed([]))),
    /** Where the pair stood its pieces, one placement per piece. */
    layout: Schema.Array(Placement).pipe(Schema.withDecodingDefaultKey(Effect.succeed([]))),
    /** The room's own furniture the pair put away; the rest of it stands where the room has it. */
    stowed: Schema.Array(RoomItemId).pipe(Schema.withDecodingDefaultKey(Effect.succeed([]))),
    /** The newest layout changes applied, so a repeated id is answered and not applied twice. */
    layoutLog: Schema.Array(IdempotencyKey).pipe(Schema.withDecodingDefaultKey(Effect.succeed([]))),
    /** The pair's local day it last opened the daily gift on. */
    giftDay: Schema.optionalKey(LocalDay),
    /** A room opened before welcome coins existed reads false and gets them on its next call. */
    welcomed: Schema.Boolean.pipe(Schema.withDecodingDefaultKey(Effect.succeed(false))),
    wallet: RoomWallet,
    /** The `rev` of the last reaction change; absent before the first. */
    lastReactionRev: Schema.optionalKey(Count),
    /** Each member's latest check-in, at most one each; a room stored before moods has none. */
    moods: Schema.Array(MoodCheckIn).pipe(Schema.withDecodingDefaultKey(Effect.succeed([]))),
  },
});
export type RoomState = typeof RoomState.Type;
export type ActiveRoom = typeof RoomState.cases.Active.Type;

/** A committed note. `seq` orders the room and is what a reconnecting client resumes from. */
export const SequencedNote = Schema.Struct({ seq: Schema.Int, note: Note });
export type SequencedNote = typeof SequencedNote.Type;

/** A cat journal entry before the room has given it a `seq`. */
export type CatEntryDraft = Omit<CatEntry, "seq">;
