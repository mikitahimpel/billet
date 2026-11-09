import { Schema } from "effect";
import { EpochMillis, MediaKey, NoteId, UserId } from "./ids.ts";
import { CompactStrokes } from "./ink.ts";
import { NoteInk } from "./inks.ts";

/** The client owns the palette; the wire carries the id. */
export const PaperColor = Schema.Literals(["butter", "blush", "sage", "sky", "cream"]);
export type PaperColor = typeof PaperColor.Type;

/** Stamp and seal ids: a client that doesn't know one shows the note without it, so an id may be
 * added but never removed or renamed. */
export const NoteStamp = Schema.Literals(["heart", "moon", "bloom", "paw", "sun"]);
export type NoteStamp = typeof NoteStamp.Type;

export const NoteSeal = Schema.Literals(["rose", "night", "meadow", "honey", "plum"]);
export type NoteSeal = typeof NoteSeal.Type;

/** Grapheme clusters. */
export const noteTextMaxCharacters = 120;

/** UTF-16 units (Swift `utf16.count`), so combining marks can't stretch 120 characters into a
 * large body. Still fits 120 of the longest emoji sequences. */
export const noteTextMaxUnits = 2048;

const graphemes = new Intl.Segmenter(undefined, { granularity: "grapheme" });

/** The same as Swift's `String.count`. */
export const characterCount = (text: string): number => {
  let count = 0;
  for (const _ of graphemes.segment(text)) count += 1;
  return count;
};

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

/** Pixels per side. The app resizes before it uploads. */
export const photoMaxSide = 8192;

export const PhotoSide = Schema.Int.check(Schema.isBetween({ minimum: 1, maximum: photoMaxSide }));
export type PhotoSide = typeof PhotoSide.Type;

const base83 =
  "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~";

/** At most 9 by 9 components: 4 header characters, and 2 for each other component. */
export const photoPreviewMaxLength = 4 + 2 * 9 * 9;

const isBlurHash = (hash: string) => {
  if (hash.length < 6 || hash.length > photoPreviewMaxLength) return false;
  for (const character of hash) if (!base83.includes(character)) return false;
  const sizeFlag = base83.indexOf(hash.charAt(0));
  if (sizeFlag > 9 * 9 - 1) return false;
  const componentsX = (sizeFlag % 9) + 1;
  const componentsY = Math.floor(sizeFlag / 9) + 1;
  return hash.length === 4 + 2 * componentsX * componentsY;
};

/** A BlurHash (https://blurha.sh), not a tiny JPEG: about 30 ASCII characters, small enough for
 * a push or a widget's 4 KB budget, with no JSON escaping and no image codec to decode. */
export const PhotoPreview = Schema.String.check(
  Schema.makeFilter(
    (hash) =>
      isBlurHash(hash) || `expected a BlurHash of at most ${photoPreviewMaxLength} characters`,
  ),
);
export type PhotoPreview = typeof PhotoPreview.Type;

/** A drawing's `compact` is for pushes, `image` a full PNG in R2. A photo's `width`, `height` and
 * `preview` are absent only on old stored photos; new ones carry them (see `SendNoteRequest`). */
export const Note = Schema.TaggedUnion({
  Drawing: {
    id: NoteId,
    author: UserId,
    sentAt: EpochMillis,
    compact: CompactStrokes,
    image: MediaKey,
    paper: Schema.optionalKey(PaperColor),
    stamp: Schema.optionalKey(NoteStamp),
    seal: Schema.optionalKey(NoteSeal),
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
    stamp: Schema.optionalKey(NoteStamp),
    seal: Schema.optionalKey(NoteSeal),
    /** A note from before inks reads as the free ink. */
    ink: NoteInk,
  },
});
export type Note = typeof Note.Type;
