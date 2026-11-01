import { Schema } from "effect";
import { MediaKey } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { Note } from "@billet/contracts-domain/note";

/** Where `POST /v1/media` stored a PNG. A note sends this key back as its `image`. */
export const UploadImageResponse = Schema.Struct({ image: MediaKey });
export type UploadImageResponse = typeof UploadImageResponse.Type;

/** The server assigns id, author and time. */
export const SendNoteRequest = Schema.TaggedUnion({
  Drawing: { compact: CompactStrokes, image: MediaKey },
  Photo: { image: MediaKey },
});
export type SendNoteRequest = typeof SendNoteRequest.Type;

export const SendNoteResponse = Schema.Struct({ note: Note });
export type SendNoteResponse = typeof SendNoteResponse.Type;

export const ListNotesResponse = Schema.Struct({ notes: Schema.Array(Note) });
export type ListNotesResponse = typeof ListNotesResponse.Type;
