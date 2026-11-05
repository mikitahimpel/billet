import { Schema } from "effect";
import { EpochMillis } from "@billet/contracts-domain/ids";

/** What a `room` row holds. A test fails if the table's columns differ. */
export const StoredRoom = Schema.Struct({
  id: Schema.Int,
  pairId: Schema.String,
  firstUser: Schema.String,
  firstPresence: Schema.String,
  secondUser: Schema.String,
  secondPresence: Schema.String,
  lastSeq: Schema.Int,
  streakDays: Schema.Int,
  lastReactionRev: Schema.NullOr(Schema.Int),
  giftDay: Schema.NullOr(Schema.String),
  welcomed: Schema.Boolean,
});

/** What a `reaction` row holds: `reaction` is null once it was taken back. */
export const StoredReaction = Schema.Struct({
  noteId: Schema.String,
  by: Schema.String,
  reaction: Schema.NullOr(Schema.String),
  at: Schema.Int,
  rev: Schema.Int,
});

/** What a `mood` row holds: one member's latest check-in. */
export const StoredMood = Schema.Struct({
  user: Schema.String,
  mood: Schema.String,
  note: Schema.NullOr(Schema.String),
  at: Schema.Int,
});

/** What a `note` row holds. */
export const StoredNote = Schema.Struct({
  seq: Schema.Int,
  body: Schema.String,
  author: Schema.NullOr(Schema.String),
  idempotencyKey: Schema.NullOr(Schema.String),
});

/** A row with every column shape a table can have, for tests that check the check. */
export const SampleRow = Schema.Struct({ id: Schema.String, createdAt: EpochMillis });

/** What a `delivery` row holds. */
/** An `owned_ink` row: one ink colour the pair bought, and its place in the order. */
export const StoredOwnedInk = Schema.Struct({
  inkId: Schema.String,
  position: Schema.Int,
});

export const StoredOwnedItem = Schema.Struct({
  itemId: Schema.String,
  position: Schema.Int,
});

export const StoredWish = Schema.Struct({
  itemId: Schema.String,
  position: Schema.Int,
});

export const StoredClaimedBonus = Schema.Struct({
  collectionId: Schema.String,
  position: Schema.Int,
});

export const StoredDelivery = Schema.Struct({
  noteId: Schema.String,
  lane: Schema.String,
  status: Schema.String,
  attempts: Schema.Int,
  nextAttemptAt: Schema.Int,
});

/** What the one `cat` row holds, once the cat is adopted. */
export const StoredCat = Schema.Struct({
  id: Schema.Int,
  name: Schema.String,
  model: Schema.String,
  coat: Schema.String,
  bornAt: Schema.Int,
  natureSeed: Schema.String,
  utcOffsetSeconds: Schema.Int,
  curious: Schema.Number,
  lazy: Schema.Number,
  cuddly: Schema.Number,
  lastSeq: Schema.Int,
  lastAt: Schema.NullOr(Schema.Int),
});

/** What a `cat_entry` row holds: `body` is the `CatEvent` as JSON. */
export const StoredCatEntry = Schema.Struct({
  seq: Schema.Int,
  id: Schema.String,
  by: Schema.String,
  at: Schema.Int,
  body: Schema.String,
});

/** What an `activity` row holds: `body` is the item's event and target as JSON. */
export const StoredActivity = Schema.Struct({
  id: Schema.String,
  sortKey: Schema.String,
  at: Schema.Int,
  doerKind: Schema.String,
  doerUser: Schema.NullOr(Schema.String),
  body: Schema.String,
});

/** What an `activity_read` row holds. */
export const StoredActivityRead = Schema.Struct({ user: Schema.String, upTo: Schema.String });

/** The one `wallet` row: the balance, and what care earned on `day` against each daily cap. */
export const StoredWallet = Schema.Struct({
  id: Schema.Int,
  balance: Schema.Int,
  day: Schema.NullOr(Schema.String),
  care: Schema.Int,
  notes: Schema.Int,
  games: Schema.Int,
  lists: Schema.Int,
});

/** A `coin_entry` row: one wallet entry, in the order it was stored. */
export const StoredCoinEntry = Schema.Struct({
  seq: Schema.Int,
  id: Schema.String,
  kind: Schema.String,
  amount: Schema.Int,
  ref: Schema.String,
  at: Schema.Int,
});
