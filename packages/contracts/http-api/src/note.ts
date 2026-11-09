import { Schema } from "effect";
import { IdempotencyKey, MediaKey } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { NoteInk } from "@billet/contracts-domain/inks";
import {
  Note,
  NoteSeal,
  NoteStamp,
  NoteText,
  PaperColor,
  PhotoPreview,
  PhotoSide,
} from "@billet/contracts-domain/note";

/** Where `POST /v1/media` stored a PNG, JPEG or HEIC. A note sends this key back as its `image`. */
export const UploadImageResponse = Schema.Struct({ image: MediaKey });
export type UploadImageResponse = typeof UploadImageResponse.Type;

/** The server sets id, author and time; a repeated `key` answers the first note. */
export const SendNoteRequest = Schema.TaggedUnion({
  Drawing: {
    key: IdempotencyKey,
    compact: CompactStrokes,
    image: MediaKey,
    paper: Schema.optionalKey(PaperColor),
    stamp: Schema.optionalKey(NoteStamp),
    seal: Schema.optionalKey(NoteSeal),
  },
  Photo: {
    key: IdempotencyKey,
    image: MediaKey,
    width: PhotoSide,
    height: PhotoSide,
    preview: PhotoPreview,
    caption: Schema.optionalKey(NoteText),
  },
  /** `ink` must be one the pair owns (`InkNotOwned` otherwise); left out, it is the free ink. */
  Text: {
    key: IdempotencyKey,
    text: NoteText,
    paper: Schema.optionalKey(PaperColor),
    stamp: Schema.optionalKey(NoteStamp),
    seal: Schema.optionalKey(NoteSeal),
    ink: NoteInk,
  },
});
export type SendNoteRequest = typeof SendNoteRequest.Type;

export const SendNoteResponse = Schema.Struct({ note: Note });
export type SendNoteResponse = typeof SendNoteResponse.Type;

/** A stored note with its place in the couple's history, the same `seq` `NoteReceived` carries. */
export const NoteEntry = Schema.Struct({ seq: Schema.Int, note: Note });
export type NoteEntry = typeof NoteEntry.Type;

/** Oldest first. The next page starts after the last entry's `seq`. */
export const ListNotesResponse = Schema.Struct({ notes: Schema.Array(NoteEntry) });
export type ListNotesResponse = typeof ListNotesResponse.Type;
