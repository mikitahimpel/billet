import { Schema } from "effect";
import { NoteId, UserId } from "@billet/contracts-domain/ids";
import { CompactStrokes } from "@billet/contracts-domain/ink";

const fields = {
  noteId: NoteId,
  author: UserId,
  /** Absent for photos, which have no vector rendition. */
  compact: Schema.optionalKey(CompactStrokes),
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
