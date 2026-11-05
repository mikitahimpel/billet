import { Schema } from "effect";
import { IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import { Note } from "@billet/contracts-domain/note";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PresenceState } from "@billet/contracts-realtime/client-message";

/** Everything that can change a room. Ids and times are settled before a command reaches `decide`. */
export const RoomCommand = Schema.TaggedUnion({
  Open: { pairId: PairId, members: Schema.Tuple([UserId, UserId]) },
  SendNote: { note: Note, key: IdempotencyKey },
  SetPresence: { user: UserId, state: PresenceState },
  /** Gives the pair ink colours, as the wallet does once it has taken their coins. */
  GrantInks: { inks: Schema.Array(InkId) },
});
export type RoomCommand = typeof RoomCommand.Type;
