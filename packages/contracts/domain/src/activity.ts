import { Schema } from "effect";
import { CatGameId, CatName } from "./cat.ts";
import { EpochMillis, NoteId } from "./ids.ts";
import { ListId, ListItemText, ListKind, ListTitle } from "./list.ts";
import { Mood } from "./mood.ts";
import { Reaction } from "./reaction.ts";

/**
 * An item's id: its source row's own, such as `cat:<entry id>`, `note:<note id>` or a coin entry's
 * `spend:<uuid>`. A repeated write is one item, and an item is found again when its source goes.
 */
export const ActivityId = Schema.String.check(
  Schema.isPattern(/^[a-z]+:[A-Za-z0-9:._-]{1,96}$/),
).pipe(Schema.brand("ActivityId"));
export type ActivityId = typeof ActivityId.Type;

const slug = Schema.String.check(Schema.isPattern(/^[a-z0-9-]{1,40}$/));

/** A shop item, such as `armchair` or `ink-rose`. The phone localises its name by id. */
export const ActivityShopItemId = slug.pipe(Schema.brand("ActivityShopItemId"));
/** A shop offer, such as `deal:2026-11-05:0` or `bundle:starter-ink`. */
export const ActivityOfferId = Schema.String.check(Schema.isPattern(/^[a-z0-9:-]{1,64}$/)).pipe(
  Schema.brand("ActivityOfferId"),
);
/** A collection whose set earned a bonus, such as `cozy-cabin`. */
export const ActivityCollectionId = slug.pipe(Schema.brand("ActivityCollectionId"));
/** A plant in the room, such as `monstera`. */
export const ActivityPlantId = slug.pipe(Schema.brand("ActivityPlantId"));
/** An App Store product, such as `com.mikitahimpel.billet.coins.small`. */
export const ActivityProductId = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9._-]{1,128}$/));

const Coins = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));

/**
 * Who did it, as the caller sees it: themselves, their partner, the cat on its own, or the App
 * Store (a refund names no user).
 */
export const ActivityActor = Schema.Literals(["Me", "Partner", "Cat", "Store"]);
export type ActivityActor = typeof ActivityActor.Type;

/** What happened. The phone writes the line from the kind and these few values. */
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
  /** The partner claimed the invite: the pair formed. */
  PartnerJoined: {},
  NoteSent: { note: NoteId, kind: Schema.Literals(["Drawing", "Photo", "Text"]) },
  /** A partner reacted to the other's photo. */
  Reacted: { note: NoteId, reaction: Reaction },
  /** A partner checked in with how they feel. */
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
  /**
   * A partner added items to a list: `count` of them within ten minutes, the latest being `text`.
   * One item per list, partner and ten minutes, so a shopping run is one line.
   */
  ListItemAdded: {
    list: ListId,
    kind: ListKind,
    title: ListTitle,
    count: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)),
    text: ListItemText,
  },
});
export type ActivityEvent = typeof ActivityEvent.Type;

/** Where tapping the item goes. */
export const ActivityTarget = Schema.TaggedUnion({
  /** A text note. */
  Note: { note: NoteId },
  /** A drawing or a photo, in Moments. */
  Moments: { note: NoteId },
  Cat: {},
  Plant: { plant: ActivityPlantId },
  ShopItem: { id: ActivityShopItemId },
  ShopOffer: { id: ActivityOfferId },
  List: { list: ListId },
});
export type ActivityTarget = typeof ActivityTarget.Type;

/** A place in the list, newest first: an opaque string the client only hands back. */
export const ActivityCursor = Schema.String.check(
  Schema.isPattern(/^[0-9]{16}~[a-z]+:[A-Za-z0-9:._-]{1,96}$/),
).pipe(Schema.brand("ActivityCursor"));
export type ActivityCursor = typeof ActivityCursor.Type;

/** One Inbox item. `cursor` is its place in the list: hand it back as `upTo` to mark it read. */
export const ActivityItem = Schema.Struct({
  id: ActivityId,
  at: EpochMillis,
  actor: ActivityActor,
  event: ActivityEvent,
  target: Schema.optionalKey(ActivityTarget),
  cursor: ActivityCursor,
});
export type ActivityItem = typeof ActivityItem.Type;

/** How long the room keeps an item. */
export const activityRetentionDays = 30;
