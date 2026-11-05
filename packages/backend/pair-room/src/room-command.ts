import { Schema } from "effect";
import {
  CatEvent,
  CatLook,
  CatName,
  NatureSeed,
  UtcOffsetSeconds,
} from "@billet/contracts-domain/cat";
import { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { InkId } from "@billet/contracts-domain/inks";
import { Note } from "@billet/contracts-domain/note";
import { PairId } from "@billet/contracts-domain/pair-id";
import { RoomItemId, ShopOffer } from "@billet/contracts-domain/shop";
import { PresenceState } from "@billet/contracts-realtime/client-message";

/** Everything that can change a room. Ids and times are settled before a command reaches `decide`. */
export const RoomCommand = Schema.TaggedUnion({
  Open: { pairId: PairId, members: Schema.Tuple([UserId, UserId]) },
  SendNote: { note: Note, key: IdempotencyKey },
  SetPresence: { user: UserId, state: PresenceState },
  /** Adopts the cat, or renames it. `natureSeed` and `at` are used only by an adoption. */
  SaveCat: {
    user: UserId,
    name: CatName,
    look: CatLook,
    utcOffsetSeconds: UtcOffsetSeconds,
    natureSeed: NatureSeed,
    at: EpochMillis,
  },
  RecordCatEvent: { id: IdempotencyKey, by: UserId, at: EpochMillis, event: CatEvent },
  /** Gives the pair ink colours, as the wallet does once it has taken their coins. */
  GrantInks: { inks: Schema.Array(InkId) },
  /** Buys one ink with the pair's coins, at its catalog price. `id` is the buyer's, once. */
  Buy: { id: IdempotencyKey, by: UserId, ink: InkId, at: EpochMillis },
  /** Buys one offer with the pair's coins, at the catalog's price. `id` is the buyer's, once. */
  Order: { id: IdempotencyKey, by: UserId, offer: ShopOffer, at: EpochMillis },
  SetWish: { by: UserId, item: RoomItemId, wished: Schema.Boolean },
});
export type RoomCommand = typeof RoomCommand.Type;
