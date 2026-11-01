import { Schema } from "effect";
import { EpochMillis, MediaKey, NoteId, UserId } from "./ids.ts";
import { CompactStrokes } from "./ink.ts";

/** A note has two renditions: compact strokes for pushes, and a full PNG in R2. */
export const Note = Schema.TaggedUnion({
  Drawing: {
    id: NoteId,
    author: UserId,
    sentAt: EpochMillis,
    compact: CompactStrokes,
    image: MediaKey,
  },
  Photo: {
    id: NoteId,
    author: UserId,
    sentAt: EpochMillis,
    image: MediaKey,
  },
});
export type Note = typeof Note.Type;
