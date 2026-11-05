import { RoomItemId } from "@billet/contracts-domain/shop";
import { Schema } from "effect";
import { CatProfile } from "@billet/contracts-domain/cat";
import { IdempotencyKey, MediaKey, NoteId, UserId } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import { Note } from "@billet/contracts-domain/note";
import { PairId } from "@billet/contracts-domain/pair-id";
import { emptyWallet, RoomState, type ActiveRoom, type RoomCat } from "../src/room-state.ts";
import { newTemper } from "../src/cat-temper.ts";

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
  items: [],
  wishlist: [],
  bonuses: [],
  welcomed: true,
  wallet: emptyWallet,
});

export const catProfile: CatProfile = Schema.decodeUnknownSync(CatProfile)({
  name: "Mochi",
  look: { model: "marmalade", coat: "natural" },
  bornAt: 1_700_000_000_000,
  natureSeed: "12345678901234567890",
  utcOffsetSeconds: 3600,
});

export const adoptedCat: RoomCat = { profile: catProfile, temper: newTemper, lastSeq: 0 };

export const withCat: ActiveRoom = { ...active, cat: adoptedCat };

/** A room the service just opened: welcomed with its coins. */
export const welcomed: ActiveRoom = { ...active, wallet: { ...emptyWallet, balance: 560 } };

/** A UUID numbered `n`, for journal ids and note keys. */
export const uuid = (n: number) =>
  Schema.decodeSync(IdempotencyKey)(`00000000-0000-4000-8000-${String(n).padStart(12, "0")}`);
export const rose = Schema.decodeUnknownSync(InkId)("ink-rose");
export const sea = Schema.decodeUnknownSync(InkId)("ink-sea");
export const tower = Schema.decodeUnknownSync(RoomItemId)("tower");

export const textFrom = (author: UserId, ink: InkId, id = "note-1"): Note =>
  Note.cases.Text.make({
    id: Schema.decodeUnknownSync(NoteId)(id),
    author,
    sentAt: 1_700_000_000_000,
    text: "hi",
    ink,
  });
