import { Data } from "effect";
import type { InkId } from "@billet/contracts-domain/inks";
import type { CollectionId } from "@billet/contracts-domain/shop";

/** The caller has no partner, or the couple has no such image: the client can't tell which. */
export class NotesNotFound extends Data.TaggedError("NotesNotFound") {}

/** The bytes aren't a PNG, or a compact rendition is over budget. */
export class InvalidNote extends Data.TaggedError("InvalidNote") {}

/** A text note in an ink colour the pair has not bought. */
export class InkNotOwned extends Data.TaggedError("InkNotOwned")<{ readonly ink: InkId }> {}

/** A buy that costs more than the pair's balance. */
export class NotEnoughCoins extends Data.TaggedError("NotEnoughCoins")<{
  readonly needed: number;
  readonly have: number;
}> {}

/** A buy of something the pair already owns: an ink, a piece, or every piece of a set. */
export class AlreadyOwned extends Data.TaggedError("AlreadyOwned")<{ readonly itemId: string }> {}

/** A bonus for a collection with a piece still missing. */
export class CollectionIncomplete extends Data.TaggedError("CollectionIncomplete")<{
  readonly collection: CollectionId;
}> {}

/** A buy for the cat, such as a treat, before the couple adopted one. */
export class CatNotAdopted extends Data.TaggedError("CatNotAdopted") {}

/** A dependency failed, so nothing changed. The client can retry; `reason` is a fixed label. */
export class NotesUnavailable extends Data.TaggedError("NotesUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}
