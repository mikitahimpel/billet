import { Schema } from "effect";
import { Stroke } from "@billet/contracts-domain/ink";

export const PresenceState = Schema.Literals(["idle", "drawing"]);
export type PresenceState = typeof PresenceState.Type;

/** Provisional until the realtime protocol (#17) is built; keeps only what the docs name. */
export const ClientMessage = Schema.TaggedUnion({
  /** Reconnect, asking for everything after `lastSeq`. */
  Resume: { lastSeq: Schema.Int },
  Stroke: { stroke: Stroke },
  Presence: { state: PresenceState },
});
export type ClientMessage = typeof ClientMessage.Type;
