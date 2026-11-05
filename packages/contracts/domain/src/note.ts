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

/** The most pixels a photo may have on either side. The app resizes before it uploads. */
export const photoMaxSide = 8192;

/** A photo's width or height in pixels, 1 to 8192. */
export const PhotoSide = Schema.Int.check(Schema.isBetween({ minimum: 1, maximum: photoMaxSide }));
export type PhotoSide = typeof PhotoSide.Type;

const base83 =
  "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~";

/**
 * A BlurHash has at most 9 by 9 components: a size flag, a maximum, 4 characters of average colour,
 * and 2 for each other component.
 */
export const photoPreviewMaxLength = 4 + 2 * 9 * 9;

/** Whether `hash` is a well-formed BlurHash: base 83 only, and as long as its header says. */
const isBlurHash = (hash: string) => {
  if (hash.length < 6 || hash.length > photoPreviewMaxLength) return false;
  for (const character of hash) if (!base83.includes(character)) return false;
  const sizeFlag = base83.indexOf(hash.charAt(0));
  if (sizeFlag > 9 * 9 - 1) return false;
  const componentsX = (sizeFlag % 9) + 1;
  const componentsY = Math.floor(sizeFlag / 9) + 1;
  return hash.length === 4 + 2 * componentsX * componentsY;
};

/**
 * A blurred stand-in for a photo, shown until the full image arrives, as a BlurHash
 * (https://blurha.sh). A BlurHash, not a tiny JPEG: it is at most 166 ASCII characters, about
 * 30 for the usual 4 by 3, small enough to ride in a push or a widget's 4 KB budget later, while a
 * useful JPEG thumbnail is a couple of kilobytes of base64. Its alphabet needs no JSON escaping,
 * its length is fixed by its first character so it is checked exactly, and decoding it on the
 * phone is a few dozen lines with no image codec.
 */
export const PhotoPreview = Schema.String.check(
  Schema.makeFilter(
    (hash) =>
      isBlurHash(hash) || `expected a BlurHash of at most ${photoPreviewMaxLength} characters`,
  ),
);
export type PhotoPreview = typeof PhotoPreview.Type;

/**
 * A drawing has two renditions: compact strokes for pushes, and a full PNG in R2. A photo has only
 * the image, a PNG, JPEG or HEIC. A text note carries its words and no image. `paper` is absent
 * when the sender chose none.
 *
 * A photo's `width`, `height` and `preview` are optional here only because photos stored before
 * they existed have none; every photo sent now carries them (see `SendNoteRequest`). `caption` is
 * absent when the sender wrote none.
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
    width: Schema.optionalKey(PhotoSide),
    height: Schema.optionalKey(PhotoSide),
    preview: Schema.optionalKey(PhotoPreview),
    caption: Schema.optionalKey(NoteText),
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
