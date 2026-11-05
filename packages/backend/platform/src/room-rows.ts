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
