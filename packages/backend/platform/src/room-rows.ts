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
  streakBest: Schema.Int,
  streakLastDay: Schema.NullOr(Schema.String),
  streakRestoredOn: Schema.NullOr(Schema.String),
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

export const StoredNote = Schema.Struct({
  seq: Schema.Int,
  body: Schema.String,
  author: Schema.NullOr(Schema.String),
  idempotencyKey: Schema.NullOr(Schema.String),
});

/** A row with every column shape a table can have, for tests that check the check. */
export const SampleRow = Schema.Struct({ id: Schema.String, createdAt: EpochMillis });

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

export const StoredPlacement = Schema.Struct({
  itemId: Schema.String,
  surface: Schema.String,
  u: Schema.Int,
  v: Schema.Int,
  quarterTurns: Schema.Int,
  position: Schema.Int,
});

export const StoredLayoutLog = Schema.Struct({
  changeId: Schema.String,
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

export const StoredGiftWish = Schema.Struct({
  id: Schema.String,
  owner: Schema.String,
  title: Schema.String,
  link: Schema.String,
  price: Schema.String,
  note: Schema.String,
  mostWanted: Schema.Int,
  occasionTitle: Schema.NullOr(Schema.String),
  occasionDate: Schema.NullOr(Schema.Int),
  addedAt: Schema.Int,
  receivedAt: Schema.NullOr(Schema.Int),
  giftedBy: Schema.NullOr(Schema.String),
});

export const StoredGiftPlan = Schema.Struct({
  wishId: Schema.String,
  giver: Schema.String,
  stage: Schema.String,
});

export const StoredGiftLoves = Schema.Struct({
  user: Schema.String,
  body: Schema.String,
});

export const StoredList = Schema.Struct({
  id: Schema.String,
  position: Schema.Int,
  kind: Schema.String,
  title: Schema.String,
  iconSymbol: Schema.String,
  iconTint: Schema.String,
});

/** What a `list_items` row holds: `wants` is a JSON array of user ids. */
export const StoredListItem = Schema.Struct({
  id: Schema.String,
  listId: Schema.String,
  position: Schema.Int,
  text: Schema.String,
  author: Schema.String,
  addedAt: Schema.Int,
  doneBy: Schema.NullOr(Schema.String),
  doneAt: Schema.NullOr(Schema.Int),
  quantity: Schema.NullOr(Schema.String),
  note: Schema.NullOr(Schema.String),
  icon: Schema.NullOr(Schema.String),
  aisle: Schema.NullOr(Schema.String),
  mediaKind: Schema.NullOr(Schema.String),
  mediaTmdb: Schema.NullOr(Schema.Int),
  mediaYear: Schema.NullOr(Schema.Int),
  mediaPoster: Schema.NullOr(Schema.String),
  country: Schema.NullOr(Schema.String),
  place: Schema.NullOr(Schema.Boolean),
  visitedIn: Schema.NullOr(Schema.String),
  moments: Schema.NullOr(Schema.String),
  wants: Schema.String,
});

export const StoredListKey = Schema.Struct({ key: Schema.String, at: Schema.Int });

export const StoredMovieSwipe = Schema.Struct({
  member: Schema.String,
  title: Schema.String,
  choice: Schema.String,
  name: Schema.String,
  posterPath: Schema.NullOr(Schema.String),
  at: Schema.Int,
});

export const StoredGuessRound = Schema.Struct({
  day: Schema.String,
  subject: Schema.String,
  questions: Schema.String,
});

export const StoredGuessAnswer = Schema.Struct({
  day: Schema.String,
  member: Schema.String,
  question: Schema.Int,
  option: Schema.Int,
  at: Schema.Int,
});

export const StoredGuessWeek = Schema.Struct({
  week: Schema.String,
  member: Schema.String,
  points: Schema.Int,
});

export const StoredRiddle = Schema.Struct({
  id: Schema.String,
  drawer: Schema.String,
  endedAt: Schema.NullOr(Schema.Int),
  body: Schema.String,
});

export const StoredRiddleGuess = Schema.Struct({
  riddle: Schema.String,
  key: Schema.String,
  right: Schema.Boolean,
  at: Schema.Int,
});

export const StoredRiddleSeries = Schema.Struct({
  id: Schema.Int,
  series: Schema.Int,
  best: Schema.Int,
});
