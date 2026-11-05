import { Schema } from "effect";
import { CatEntry, CatProfile } from "@billet/contracts-domain/cat";
import { Color, Stroke } from "@billet/contracts-domain/ink";
import { Note } from "@billet/contracts-domain/note";
import { NoteReaction } from "@billet/contracts-domain/reaction";
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
  /** One cat journal entry, either partner's, sent once to each socket that resumed the journal. */
  CatEntryAdded: { entry: CatEntry },
  /** The cat was adopted, renamed or given a new look. */
  CatSaved: { cat: CatProfile },
  /** The user's Inbox count changed, sent to sockets that resumed with `activity: true`. */
  ActivityUnread: { unread: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)) },
  /** A reaction was set or taken back, sent to sockets that resumed with `lastReactionRev`. */
  ReactionChanged: { reaction: NoteReaction },
});
export type ServerMessage = typeof ServerMessage.Type;
