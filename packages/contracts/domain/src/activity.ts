import { Schema } from "effect";
import { CatGameId, CatName } from "./cat.ts";
import { EpochMillis, NoteId } from "./ids.ts";
import { ListId, ListItemText, ListKind, ListTitle } from "./list.ts";
import { Mood } from "./mood.ts";
import { Reaction } from "./reaction.ts";

/** The source row's own id, such as `note:<note id>`, so a repeated write is one item and an
 * item is found again when its source goes. */
export const ActivityId = Schema.String.check(
  Schema.isPattern(/^[a-z]+:[A-Za-z0-9:._-]{1,96}$/),
).pipe(Schema.brand("ActivityId"));
export type ActivityId = typeof ActivityId.Type;

const slug = Schema.String.check(Schema.isPattern(/^[a-z0-9-]{1,40}$/));

/** The phone localises its name by id. */
export const ActivityShopItemId = slug.pipe(Schema.brand("ActivityShopItemId"));
export const ActivityOfferId = Schema.String.check(Schema.isPattern(/^[a-z0-9:-]{1,64}$/)).pipe(
  Schema.brand("ActivityOfferId"),
);
export const ActivityCollectionId = slug.pipe(Schema.brand("ActivityCollectionId"));
export const ActivityPlantId = slug.pipe(Schema.brand("ActivityPlantId"));
export const ActivityProductId = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9._-]{1,128}$/));

const Coins = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/** As the caller sees it. `Store`: a refund names no user. */
export const ActivityActor = Schema.Literals(["Me", "Partner", "Cat", "Store"]);
export type ActivityActor = typeof ActivityActor.Type;

/** The phone writes the line from the kind and these few values. */
export const ActivityEvent = Schema.TaggedUnion({
  CatFed: { grams: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)) },
  CatPetted: {},
  CatPlayed: {},
  CatGamePlayed: {
    game: CatGameId,
    score: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
    won: Schema.Boolean,
  },
  CatSlept: {},
  CatShooed: {},
  /** `plant` is absent for the one plant by the window that came before plants had ids. */
  PlantWatered: { plant: Schema.optionalKey(ActivityPlantId) },
  CatAdopted: { name: CatName },
  CatRenamed: { name: CatName },
  PartnerJoined: {},
  NoteSent: { note: NoteId, kind: Schema.Literals(["Drawing", "Photo", "Text"]) },
  Reacted: { note: NoteId, reaction: Reaction },
  MoodShared: { mood: Mood },
  Purchased: {
    offer: Schema.optionalKey(ActivityOfferId),
    items: Schema.Array(ActivityShopItemId).check(Schema.isNonEmpty()),
    coins: Coins,
  },
  GiftClaimed: { coins: Coins },
  BonusEarned: { collection: ActivityCollectionId, coins: Coins },
  CoinsBought: { productId: ActivityProductId, coins: Coins },
  Refunded: { productId: ActivityProductId, coins: Coins },
  StreakReached: { days: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)) },
  /** One item per list, partner and ten minutes, so a shopping run is one line; `text` is the
   * latest. */
  ListItemAdded: {
    list: ListId,
    kind: ListKind,
    title: ListTitle,
    count: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
    text: ListItemText,
  },
});
export type ActivityEvent = typeof ActivityEvent.Type;

export const ActivityTarget = Schema.TaggedUnion({
  Note: { note: NoteId },
  /** A drawing or a photo. */
  Moments: { note: NoteId },
  Cat: {},
  Plant: { plant: ActivityPlantId },
  ShopItem: { id: ActivityShopItemId },
  ShopOffer: { id: ActivityOfferId },
  List: { list: ListId },
});
export type ActivityTarget = typeof ActivityTarget.Type;

/** Opaque: the client only hands it back. */
export const ActivityCursor = Schema.String.check(
  Schema.isPattern(/^[0-9]{16}~[a-z]+:[A-Za-z0-9:._-]{1,96}$/),
).pipe(Schema.brand("ActivityCursor"));
export type ActivityCursor = typeof ActivityCursor.Type;

/** Hand `cursor` back as `upTo` to mark the item read. */
export const ActivityItem = Schema.Struct({
  id: ActivityId,
  at: EpochMillis,
  actor: ActivityActor,
  event: ActivityEvent,
  target: Schema.optionalKey(ActivityTarget),
  cursor: ActivityCursor,
});
export type ActivityItem = typeof ActivityItem.Type;

export const activityRetentionDays = 30;
