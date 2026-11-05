import { Schema } from "effect";
import { CatEntry, CatProfile, CatTemper } from "@billet/contracts-domain/cat";
import { LocalDay } from "@billet/contracts-domain/coins";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import { Note } from "@billet/contracts-domain/note";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PresenceState } from "@billet/contracts-realtime/client-message";

/** A partner and their presence, kept together so presence cannot exist for a stranger. */
export const Member = Schema.Struct({ user: UserId, presence: PresenceState });
export type Member = typeof Member.Type;

const Count = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** Two different people: a room cannot be built around one user twice. */
const Couple = Schema.Tuple([Member, Member]).check(
  Schema.makeFilter(([first, second]) =>
    first.user === second.user ? "a room needs two different members" : true,
  ),
);

/**
 * The couple's cat, without its journal: the journal is unbounded, so it stays in the store, and
 * `lastSeq` and `lastAt` are the only parts of it a decision needs.
 */
export const RoomCat = Schema.Struct({
  profile: CatProfile,
  temper: CatTemper,
  lastSeq: Count,
  /** When the last entry was stored, absent before the first. The temper reads the gap. */
  lastAt: Schema.optionalKey(EpochMillis),
});
export type RoomCat = typeof RoomCat.Type;

/**
 * The pair's coins: the balance, and what care has earned on `day` against each daily cap. The
 * entries are unbounded, so they stay in the store.
 */
export const RoomWallet = Schema.Struct({
  balance: Count,
  /** The local day the earned counts are for, absent before the first coin is earned. */
  day: Schema.optionalKey(LocalDay),
  care: Count,
  notes: Count,
  games: Count,
});
export type RoomWallet = typeof RoomWallet.Type;

export const emptyWallet: RoomWallet = { balance: 0, care: 0, notes: 0, games: 0 };

/**
 * What one couple's room knows, except the notes themselves: those are unbounded, so they stay
 * in the store and `lastSeq` is the only part of them that a decision needs.
 *
 * `streakDays` is stored but nothing changes it yet: the rules arrive with #20.
 *
 * `inks` are the ink colours the pair has bought, in the order it got them. The free ink is
 * everyone's and never listed.
 */
export const RoomState = Schema.TaggedUnion({
  /** A new object, not given to a couple yet. */
  Vacant: {},
  Active: {
    pairId: PairId,
    members: Couple,
    lastSeq: Count,
    streakDays: Count,
    /** Absent until one of the couple adopts the cat. */
    cat: Schema.optionalKey(RoomCat),
    inks: Schema.Array(InkId),
    wallet: RoomWallet,
    /** The `rev` of the last reaction change; absent before the first. */
    lastReactionRev: Schema.optionalKey(Count),
  },
});
export type RoomState = typeof RoomState.Type;
export type ActiveRoom = typeof RoomState.cases.Active.Type;

/** A committed note. `seq` orders the room and is what a reconnecting client resumes from. */
export const SequencedNote = Schema.Struct({ seq: Schema.Int, note: Note });
export type SequencedNote = typeof SequencedNote.Type;

/** A cat journal entry before the room has given it a `seq`. */
export type CatEntryDraft = Omit<CatEntry, "seq">;
