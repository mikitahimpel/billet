import { Schema } from "effect";
import { MediaKey, NoteId, UserId } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import { Note } from "@billet/contracts-domain/note";
import { PairId } from "@billet/contracts-domain/pair-id";
import { RoomState, type ActiveRoom } from "../src/room-state.ts";

export const alice = Schema.decodeUnknownSync(UserId)("user-alice");
export const bob = Schema.decodeUnknownSync(UserId)("user-bob");
export const mallory = Schema.decodeUnknownSync(UserId)("user-mallory");
export const pairId = Schema.decodeUnknownSync(PairId)("pair-1");
export const otherPairId = Schema.decodeUnknownSync(PairId)("pair-2");
export const image = Schema.decodeUnknownSync(MediaKey)("pairs/pair-1/notes/note-1.png");

export const photoFrom = (author: UserId, id = "note-1"): Note =>
  Note.cases.Photo.make({
    id: Schema.decodeUnknownSync(NoteId)(id),
    author,
    sentAt: 1_700_000_000_000,
    image,
  });

export const vacant: RoomState = RoomState.cases.Vacant.make({});

export const active: ActiveRoom = RoomState.cases.Active.make({
  pairId,
  members: [
    { user: alice, presence: "idle" },
    { user: bob, presence: "idle" },
  ],
  lastSeq: 0,
  streakDays: 0,
  inks: [],
});

export const rose = Schema.decodeUnknownSync(InkId)("ink-rose");
export const sea = Schema.decodeUnknownSync(InkId)("ink-sea");

export const textFrom = (author: UserId, ink: InkId, id = "note-1"): Note =>
  Note.cases.Text.make({
    id: Schema.decodeUnknownSync(NoteId)(id),
    author,
    sentAt: 1_700_000_000_000,
    text: "hi",
    ink,
  });
