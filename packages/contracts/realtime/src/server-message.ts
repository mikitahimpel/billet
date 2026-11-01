import { Schema } from "effect";
import { Stroke } from "@billet/contracts-domain/ink";
import { Note } from "@billet/contracts-domain/note";
import { PresenceState } from "./client-message.ts";

/** Provisional until the realtime protocol (#17) is built. `seq` supports reconnect. */
export const ServerMessage = Schema.TaggedUnion({
  Stroke: { seq: Schema.Int, stroke: Stroke },
  Presence: { state: PresenceState },
  NoteReceived: { seq: Schema.Int, note: Note },
});
export type ServerMessage = typeof ServerMessage.Type;
