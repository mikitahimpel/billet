import { Schema } from "effect";
import { IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { Note } from "@billet/contracts-domain/note";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PresenceState } from "@billet/contracts-realtime/client-message";

/** Everything that can change a room. Ids and times are settled before a command reaches `decide`. */
export const RoomCommand = Schema.TaggedUnion({
  Open: { pairId: PairId, members: Schema.Tuple([UserId, UserId]) },
  SendNote: { note: Note, key: IdempotencyKey },
  SetPresence: { user: UserId, state: PresenceState },
});
export type RoomCommand = typeof RoomCommand.Type;
