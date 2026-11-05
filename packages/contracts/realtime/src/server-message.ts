import { Schema } from "effect";
import { Color, Stroke } from "@billet/contracts-domain/ink";
import { Note } from "@billet/contracts-domain/note";
import { LivePoints, LiveStrokeId, PresenceState } from "./client-message.ts";

/**
 * What the room sends a device. `seq` supports reconnect. The live stroke frames are the
 * partner's, relayed as they arrive and never stored or replayed.
 */
export const ServerMessage = Schema.TaggedUnion({
  Stroke: { seq: Schema.Int, stroke: Stroke },
  Presence: { state: PresenceState },
  NoteReceived: { seq: Schema.Int, note: Note },
  StrokeBegin: { id: LiveStrokeId, color: Color, width: Schema.Finite },
  StrokePoints: { id: LiveStrokeId, points: LivePoints },
  StrokeEnd: { id: LiveStrokeId },
  /** The partner's device left with this stroke still open: discard it, it will not end. */
  StrokeDropped: { id: LiveStrokeId },
  Clear: {},
});
export type ServerMessage = typeof ServerMessage.Type;
