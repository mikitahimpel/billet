import { Schema } from "effect";
import { EpochMillis, MediaKey, NoteId, UserId } from "./ids.ts";
import { CompactStrokes } from "./ink.ts";

/** The paper a note is written or drawn on. The client owns the palette; the wire carries the id. */
export const PaperColor = Schema.Literals(["butter", "blush", "sage", "sky", "cream"]);
export type PaperColor = typeof PaperColor.Type;

/** The most characters a text note holds, counted as the user sees them (grapheme clusters). */
export const noteTextMaxCharacters = 120;

/**
 * A cap on UTF-16 units, so 120 characters can't be stretched into a large body with combining
 * marks. 2048 still fits 120 of the longest emoji sequences. A Swift string's `utf16.count`
 * measures the same thing.
 */
export const noteTextMaxUnits = 2048;

const graphemes = new Intl.Segmenter(undefined, { granularity: "grapheme" });

/** How many characters a person would count in `text`, the same as Swift's `String.count`. */
export const characterCount = (text: string): number => {
  let count = 0;
  for (const _ of graphemes.segment(text)) count += 1;
  return count;
};

/** What a text note says: 1 to 120 characters, not only whitespace. */
export const NoteText = Schema.String.check(
  Schema.makeFilter(
    (text) =>
      (text.trim().length > 0 &&
        text.length <= noteTextMaxUnits &&
        characterCount(text) <= noteTextMaxCharacters) ||
      `expected 1 to ${noteTextMaxCharacters} characters, not only whitespace`,
  ),
);
export type NoteText = typeof NoteText.Type;

/**
 * A drawing has two renditions: compact strokes for pushes, and a full PNG in R2. A photo has only
 * the PNG. A text note carries its words and no image. `paper` is absent when the sender chose none.
 */
export const Note = Schema.TaggedUnion({
  Drawing: {
    id: NoteId,
    author: UserId,
    sentAt: EpochMillis,
    compact: CompactStrokes,
    image: MediaKey,
    paper: Schema.optionalKey(PaperColor),
  },
  Photo: {
    id: NoteId,
    author: UserId,
    sentAt: EpochMillis,
    image: MediaKey,
  },
  Text: {
    id: NoteId,
    author: UserId,
    sentAt: EpochMillis,
    text: NoteText,
    paper: Schema.optionalKey(PaperColor),
  },
});
export type Note = typeof Note.Type;
