import { Schema } from "effect";
import { NoteId, UserId } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";
import { NoteText, PaperColor } from "@billet/contracts-domain/note";
import { Reaction } from "@billet/contracts-domain/reaction";

const fields = {
  noteId: NoteId,
  author: UserId,
  /** Drawings only. */
  compact: Schema.optionalKey(CompactStrokes),
  /** Text notes only, so a widget can show the words without a fetch. */
  text: Schema.optionalKey(NoteText),
  paper: Schema.optionalKey(PaperColor),
};

/** The key beside `aps` in an alert or widget push's JSON. */
export const pushPayloadKey = "billet";

/** Not the whole APNs envelope. `LiveActivity` is a `content-state` with the strokes always,
 * since the activity cannot use the network; the whole push stays under APNs' 4 KB. */
export const PushPayload = Schema.TaggedUnion({
  Widget: fields,
  Alert: fields,
  /** To the photo's author. */
  Reaction: { noteId: NoteId, by: UserId, reaction: Reaction },
  LiveActivity: {
    noteId: NoteId,
    author: UserId,
    compact: CompactStrokes,
    paper: Schema.optionalKey(PaperColor),
  },
});
export type PushPayload = typeof PushPayload.Type;
