import { Schema } from "effect";
import { IdempotencyKey, MediaKey } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { Note } from "@billet/contracts-domain/note";

/** Where `POST /v1/media` stored a PNG. A note sends this key back as its `image`. */
export const UploadImageResponse = Schema.Struct({ image: MediaKey });
export type UploadImageResponse = typeof UploadImageResponse.Type;

/**
 * The server assigns id, author and time. Sending the same `key` again returns the first note
 * instead of storing another.
 */
export const SendNoteRequest = Schema.TaggedUnion({
  Drawing: { key: IdempotencyKey, compact: CompactStrokes, image: MediaKey },
  Photo: { key: IdempotencyKey, image: MediaKey },
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
