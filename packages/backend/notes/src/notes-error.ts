import { Data } from "effect";

/** The caller has no partner, or the couple has no such image: the client can't tell which. */
export class NotesNotFound extends Data.TaggedError("NotesNotFound") {}

/** The bytes aren't a PNG, or a compact rendition is over budget. */
export class InvalidNote extends Data.TaggedError("InvalidNote") {}

/** A dependency failed, so nothing changed. The client can retry; `reason` is a fixed label. */
export class NotesUnavailable extends Data.TaggedError("NotesUnavailable")<{
  readonly reason: string;
}> {}
