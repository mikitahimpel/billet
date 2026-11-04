import { Schema } from "effect";
import { NoteId, UserId } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { NoteText, PaperColor } from "@billet/contracts-domain/note";

const fields = {
  noteId: NoteId,
  author: UserId,
  /** Present for drawings only: photos and text notes have no vector rendition. */
  compact: Schema.optionalKey(CompactStrokes),
  /** Present for text notes only, so a widget can show the words without a fetch. */
  text: Schema.optionalKey(NoteText),
  /** The note's paper, when the sender chose one. */
  paper: Schema.optionalKey(PaperColor),
};

/**
 * Custom data carried by a push, not the whole APNs envelope. Live Activity payloads wait
 * for the go/no-go in #13.
 */
export const PushPayload = Schema.TaggedUnion({
  Widget: fields,
  Alert: fields,
});
export type PushPayload = typeof PushPayload.Type;
