import { Data } from "effect";
import type { RiddleRefusal } from "@billet/backend-pair-room/riddle-rules";
import type { LocalDay } from "@billet/contracts-domain/coins";
import type { InkId } from "@billet/contracts-domain/inks";
import type { CollectionId } from "@billet/contracts-domain/shop";

/** The caller has no partner, or the couple has no such image: the client can't tell which. */
export class NotesNotFound extends Data.TaggedError("NotesNotFound") {}

/** The bytes aren't a PNG, or a compact rendition is over budget. */
export class InvalidNote extends Data.TaggedError("InvalidNote") {}

/** A text note in an ink colour the pair has not bought. */
export class InkNotOwned extends Data.TaggedError("InkNotOwned")<{ readonly ink: InkId }> {}

export class NotEnoughCoins extends Data.TaggedError("NotEnoughCoins")<{
  readonly needed: number;
  readonly have: number;
}> {}

/** The price is now above the one the buyer saw; nothing was charged. `price` is the new one. */
export class PriceChanged extends Data.TaggedError("PriceChanged")<{ readonly price: number }> {}

/** A buy of something the pair already owns: an ink, a piece, or every piece of a set. */
export class AlreadyOwned extends Data.TaggedError("AlreadyOwned")<{ readonly itemId: string }> {}

export class CollectionIncomplete extends Data.TaggedError("CollectionIncomplete")<{
  readonly collection: CollectionId;
}> {}

/** A placement the room refused: the piece is not the pair's, or does not fit there. */
export class LayoutRefused extends Data.TaggedError("LayoutRefused")<{
  readonly reason: "not-owned" | "unknown-piece" | "wrong-surface" | "outside-room" | "occupied";
}> {}

/** The day's gift is already open, and its entry is no longer there to repeat. */
export class GiftTaken extends Data.TaggedError("GiftTaken")<{ readonly day: LocalDay }> {}

/** A collection's bonus already paid, and its entry is no longer there to repeat. */
export class BonusTaken extends Data.TaggedError("BonusTaken")<{
  readonly collection: CollectionId;
}> {}

/** A buy for the cat, such as a treat, before the couple adopted one. */
export class CatNotAdopted extends Data.TaggedError("CatNotAdopted") {}

/** A round whose day is over, a question not in the round, or a second answer to one. */
export class GuessRefused extends Data.TaggedError("GuessRefused")<{
  readonly reason: "RoundClosed" | "NotInRound" | "Answered";
}> {}

/** `BadWord` is a bad request, `NotFound` an unknown riddle, the rest a conflict. */
export class RiddleRefused extends Data.TaggedError("RiddleRefused")<{
  readonly reason: Exclude<RiddleRefusal, "NotOpen">;
}> {}

/** A dependency failed, so nothing changed. The client can retry; `reason` is a fixed label. */
export class NotesUnavailable extends Data.TaggedError("NotesUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}

/** A restore of a streak that is alive, too short, out for longer than a day, or in cooldown. */
export class StreakNotRestorable extends Data.TaggedError("StreakNotRestorable") {}
