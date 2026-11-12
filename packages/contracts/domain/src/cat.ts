import { Schema } from "effect";
import { EpochMillis, IdempotencyKey, NoteId, UserId } from "./ids.ts";

/** Unicode scalars, the same count Swift's `CatName` makes. */
export const catNameMaxScalars = 24;

const controlCharacter = /\p{Cc}/u;

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

/** How the app words the cat: "she", "he" or "they". Either partner chooses; the room keeps the last. */
export const CatPronouns = Schema.Literals(["she", "he", "they"]);
export type CatPronouns = typeof CatPronouns.Type;

/** From the app's own catalog. The server only keeps it. */
export const CatLookId = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9_-]{1,40}$/)).pipe(
  Schema.brand("CatLookId"),
);
export type CatLookId = typeof CatLookId.Type;

export const CatLook = Schema.Struct({ model: CatLookId, coat: CatLookId });
export type CatLook = typeof CatLook.Type;

/** A UInt64 in decimal: JSON numbers cannot hold one. Both phones derive the cat's personality
 * from it; moment-to-moment choices use a seed each phone draws at launch. */
export const NatureSeed = Schema.String.check(
  Schema.makeFilter(
    (seed) =>
      (/^[1-9][0-9]{0,19}$/.test(seed) && BigInt(seed) <= 0xffff_ffff_ffff_ffffn) ||
      "expected a nonzero UInt64 in decimal",
  ),
).pipe(Schema.brand("NatureSeed"));
export type NatureSeed = typeof NatureSeed.Type;

export const UtcOffsetSeconds = Schema.Int.check(
  Schema.isBetween({ minimum: -14 * 3600, maximum: 14 * 3600 }),
);
export type UtcOffsetSeconds = typeof UtcOffsetSeconds.Type;

/** `bornAt` and `natureSeed` are set once, at adoption. */
export const CatProfile = Schema.Struct({
  name: CatName,
  /** Absent until chosen; the apps word the cat neutrally then. */
  pronouns: Schema.optionalKey(CatPronouns),
  look: CatLook,
  bornAt: EpochMillis,
  natureSeed: NatureSeed,
  /** For the hour the cat's day rhythm reads. */
  utcOffsetSeconds: UtcOffsetSeconds,
});
export type CatProfile = typeof CatProfile.Type;

export const CatGameId = Schema.String.check(Schema.isPattern(/^[a-z0-9-]{1,32}$/)).pipe(
  Schema.brand("CatGameId"),
);
export type CatGameId = typeof CatGameId.Type;

/** The room journals its `GamePlayed` itself, with the round's coins as `score`, and refuses one
 * sent by an app. */
export const drawGuessGame = Schema.decodeSync(CatGameId)("draw-guess");

/** Grams. */
export const catMealMaxGrams = 500;

/** `NoteShared` is written by the room when a note is stored, never sent by a client: one entry
 * per note, filling Loved for both partners. */
export const CatEvent = Schema.TaggedUnion({
  Fed: { grams: Schema.Int.check(Schema.isBetween({ minimum: 1, maximum: catMealMaxGrams })) },
  Petted: {},
  Played: {},
  /** It fills no need. */
  Watered: {},
  /** `kind` is the note's `_tag`, so a moment (a photo) can count for more than a word. */
  NoteShared: { note: NoteId, kind: Schema.Literals(["Drawing", "Photo", "Text"]) },
  GamePlayed: {
    game: CatGameId,
    score: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
    won: Schema.Boolean,
  },
  Slept: {},
  Shooed: {},
});
export type CatEvent = typeof CatEvent.Type;

/** `at` is the server's clock. `id` is repeated on every retry; the room keeps one entry per id.
 * A reconnecting phone resumes from `seq`. */
export const CatEntry = Schema.Struct({
  seq: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
  id: IdempotencyKey,
  by: UserId,
  at: EpochMillis,
  event: CatEvent,
});
export type CatEntry = typeof CatEntry.Type;

const Trait = Schema.Number.check(Schema.isBetween({ minimum: 0, maximum: 1 }));

/** Each from 0.1 to 0.9, 0.5 at adoption. The phone weights its brain's traits by them; they
 * never fix what the cat does. */
export const CatTemper = Schema.Struct({ curious: Trait, lazy: Trait, cuddly: Trait });
export type CatTemper = typeof CatTemper.Type;

/** Folded from the journal with the app's `PetLife` curves. */
export const CatNeeds = Schema.Struct({
  at: EpochMillis,
  full: Trait,
  rested: Trait,
  loved: Trait,
  playful: Trait,
  mood: Trait,
  asleep: Schema.Boolean,
  /** Set when one partner has cared for the cat much less than the other. */
  missing: Schema.optionalKey(UserId),
});
export type CatNeeds = typeof CatNeeds.Type;
