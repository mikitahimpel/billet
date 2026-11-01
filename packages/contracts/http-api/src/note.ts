import { Schema } from "effect";
import { MediaKey } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { Note } from "@billet/contracts-domain/note";

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
