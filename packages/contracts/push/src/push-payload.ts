import { Schema } from "effect";
import { NoteId, UserId } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { NoteText, PaperColor } from "@billet/contracts-domain/note";
import { Reaction } from "@billet/contracts-domain/reaction";

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

/** The key in an alert or widget push's JSON that holds its `PushPayload`, beside `aps`. */
export const pushPayloadKey = "billet";

/**
 * Custom data carried by a push, not the whole APNs envelope. `LiveActivity` is the
 * `content-state` of a drawing's Live Activity: the compact strokes always, since the activity
 * cannot use the network, and the whole push stays under APNs' 4 KB.
 */
export const PushPayload = Schema.TaggedUnion({
  Widget: fields,
  Alert: fields,
  /** An alert to a photo's author: `by` reacted to their note `noteId`. */
  Reaction: { noteId: NoteId, by: UserId, reaction: Reaction },
  LiveActivity: {
    noteId: NoteId,
    author: UserId,
    compact: CompactStrokes,
    paper: Schema.optionalKey(PaperColor),
  },
});
export type PushPayload = typeof PushPayload.Type;
