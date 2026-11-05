import { Schema } from "effect";
import { EpochMillis, IdempotencyKey, NoteId, UserId } from "./ids.ts";

/** The most Unicode scalars a cat's name holds, the same count Swift's `CatName` makes. */
export const catNameMaxScalars = 24;

const controlCharacter = /\p{Cc}/u;

/** A cat's name: trimmed, 1 to 24 Unicode scalars, no control characters. */
export const CatName = Schema.String.check(
  Schema.makeFilter(
    (name) =>
      (name.length > 0 &&
        name === name.trim() &&
        [...name].length <= catNameMaxScalars &&
        !controlCharacter.test(name)) ||
      `expected a trimmed name of 1 to ${catNameMaxScalars} characters, without control characters`,
  ),
).pipe(Schema.brand("CatName"));
export type CatName = typeof CatName.Type;

/** An id from the app's own catalog, such as `marmalade` or `greyWhite`. The server only keeps it. */
export const CatLookId = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9_-]{1,40}$/)).pipe(
  Schema.brand("CatLookId"),
);
export type CatLookId = typeof CatLookId.Type;

/** Which cat the couple chose and the coat it wears. */
export const CatLook = Schema.Struct({ model: CatLookId, coat: CatLookId });
export type CatLook = typeof CatLook.Type;

/**
 * The seed of the cat's nature, a UInt64 in decimal: JSON numbers cannot hold one. Both phones derive
 * the cat's personality from it. Moment-to-moment choices use a seed each phone draws at launch.
 */
export const NatureSeed = Schema.String.check(
  Schema.makeFilter(
    (seed) =>
      (/^[1-9][0-9]{0,19}$/.test(seed) && BigInt(seed) <= 0xffff_ffff_ffff_ffffn) ||
      "expected a nonzero UInt64 in decimal",
  ),
).pipe(Schema.brand("NatureSeed"));
export type NatureSeed = typeof NatureSeed.Type;

/** Fourteen hours either side of UTC, in seconds. */
export const UtcOffsetSeconds = Schema.Int.check(
  Schema.isBetween({ minimum: -14 * 3600, maximum: 14 * 3600 }),
);
export type UtcOffsetSeconds = typeof UtcOffsetSeconds.Type;

/** The facts of the couple's cat. `bornAt` and `natureSeed` are set once, when it is adopted. */
export const CatProfile = Schema.Struct({
  name: CatName,
  look: CatLook,
  bornAt: EpochMillis,
  natureSeed: NatureSeed,
  /** The pair's clock, for the hour the cat's day rhythm reads. */
  utcOffsetSeconds: UtcOffsetSeconds,
});
export type CatProfile = typeof CatProfile.Type;

/** One of the app's mini-games, such as `laser` or `yarn`. */
export const CatGameId = Schema.String.check(Schema.isPattern(/^[a-z0-9-]{1,32}$/)).pipe(
  Schema.brand("CatGameId"),
);
export type CatGameId = typeof CatGameId.Type;

/** The most a meal may weigh, in grams. */
export const catMealMaxGrams = 500;

/**
 * Something one of the couple did for the cat. `NoteShared` is written by the room when a note is
 * stored, never sent by a client: a note sent and received is one entry, and it fills Loved for
 * both partners.
 */
export const CatEvent = Schema.TaggedUnion({
  Fed: { grams: Schema.Int.check(Schema.isBetween({ minimum: 1, maximum: catMealMaxGrams })) },
  Petted: {},
  Played: {},
  /** The plant by the window. It fills no need. */
  Watered: {},
  /** `kind` is the note's `_tag`, so a moment (a photo) can count for more than a word. */
  NoteShared: { note: NoteId, kind: Schema.Literals(["Drawing", "Photo", "Text"]) },
  GamePlayed: {
    game: CatGameId,
    score: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
    won: Schema.Boolean,
  },
  /** Put to bed, or curled up. */
  Slept: {},
  /** Shooed off where it sat, the desk or the cardigan. */
  Shooed: {},
});
export type CatEvent = typeof CatEvent.Type;

/**
 * A journal entry: an event with who did it and when, by the server's clock. `id` is the UUID the
 * phone made for it, repeated on every retry; the room keeps one entry per id. `seq` orders the
 * couple's journal and is what a reconnecting phone resumes from.
 */
export const CatEntry = Schema.Struct({
  seq: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
  id: IdempotencyKey,
  by: UserId,
  at: EpochMillis,
  event: CatEvent,
});
export type CatEntry = typeof CatEntry.Type;

const Trait = Schema.Number.check(Schema.isBetween({ minimum: 0, maximum: 1 }));

/**
 * How the couple's treatment has slowly shaped the cat, each from 0.1 to 0.9 and 0.5 at adoption.
 * The phone weights its brain's traits by them; they never fix what the cat does.
 */
export const CatTemper = Schema.Struct({ curious: Trait, lazy: Trait, cuddly: Trait });
export type CatTemper = typeof CatTemper.Type;

/** The cat's needs at `at`, folded from the journal with the app's `PetLife` curves. */
export const CatNeeds = Schema.Struct({
  at: EpochMillis,
  full: Trait,
  rested: Trait,
  loved: Trait,
  playful: Trait,
  mood: Trait,
  asleep: Schema.Boolean,
  /** The partner the cat misses, when one has cared for it much less than the other. */
  missing: Schema.optionalKey(UserId),
});
export type CatNeeds = typeof CatNeeds.Type;
