import { Schema } from "effect";
import { UserId } from "@billet/contracts-domain/ids";
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
 * What one couple's room knows, except the notes themselves: those are unbounded, so they stay
 * in the store and `lastSeq` is the only part of them that a decision needs.
 *
 * `streakDays` is stored but nothing changes it yet: the rules arrive with #20.
 */
export const RoomState = Schema.TaggedUnion({
  /** A new object, not given to a couple yet. */
  Vacant: {},
  Active: {
    pairId: PairId,
    members: Couple,
    lastSeq: Count,
    streakDays: Count,
  },
});
export type RoomState = typeof RoomState.Type;
export type ActiveRoom = typeof RoomState.cases.Active.Type;

/** A committed note. `seq` orders the room and is what a reconnecting client resumes from. */
export const SequencedNote = Schema.Struct({ seq: Schema.Int, note: Note });
export type SequencedNote = typeof SequencedNote.Type;
