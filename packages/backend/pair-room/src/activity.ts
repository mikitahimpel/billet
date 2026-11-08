import { Schema } from "effect";
import {
  ActivityCollectionId,
  ActivityCursor,
  ActivityEvent,
  ActivityId,
  ActivityOfferId,
  ActivityShopItemId,
  ActivityTarget,
  activityRetentionDays,
  type ActivityActor,
  type ActivityItem,
} from "@billet/contracts-domain/activity";
import type { CatEntry } from "@billet/contracts-domain/cat";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type { Note } from "@billet/contracts-domain/note";
import { listWindowOf } from "./lists.ts";
import type { RoomOutput } from "./room-decision.ts";

/** Who did it, as stored: a member, the cat on its own, or the App Store. */
export const ActivityDoer = Schema.TaggedUnion({
  Member: { user: UserId },
  Cat: {},
  Store: {},
});
export type ActivityDoer = typeof ActivityDoer.Type;

/** One stored Inbox item. The caller sees `doer` as `Me`, `Partner`, `Cat` or `Store`. */
export const ActivityRow = Schema.Struct({
  id: ActivityId,
  at: EpochMillis,
  doer: ActivityDoer,
  event: ActivityEvent,
  target: Schema.optionalKey(ActivityTarget),
});
export type ActivityRow = typeof ActivityRow.Type;

const decodeId = Schema.decodeSync(ActivityId);
const decodeCursor = Schema.decodeSync(ActivityCursor);

/** How long an item is kept. */
export const activityRetentionMillis = activityRetentionDays * 86_400_000;

/** The place of a row in the list: sorts as the list does, by time, then by id. */
export const cursorOf = (row: Pick<ActivityRow, "at" | "id">): ActivityCursor =>
  decodeCursor(`${String(row.at).padStart(16, "0")}~${row.id}`);

const member = (user: UserId): ActivityDoer => ({ _tag: "Member", user });

/** A journal entry's item. A note's entry has none: the note makes its own. */
export const activityForCatEntry = (entry: CatEntry): ActivityRow | undefined => {
  const base = { id: decodeId(`cat:${entry.id}`), at: entry.at, doer: member(entry.by) };
  const cat = { target: ActivityTarget.cases.Cat.make({}) };
  const { event } = entry;
  switch (event._tag) {
    case "Fed":
      return { ...base, ...cat, event: { _tag: "CatFed", grams: event.grams } };
    case "Petted":
      return { ...base, ...cat, event: { _tag: "CatPetted" } };
    case "Played":
      return { ...base, ...cat, event: { _tag: "CatPlayed" } };
    case "GamePlayed":
      return {
        ...base,
        ...cat,
        event: { _tag: "CatGamePlayed", game: event.game, score: event.score, won: event.won },
      };
    case "Slept":
      return { ...base, ...cat, event: { _tag: "CatSlept" } };
    case "Shooed":
      return { ...base, ...cat, event: { _tag: "CatShooed" } };
    // The one plant by the window has no id yet; plants with ids bring their own target.
    case "Watered":
      return { ...base, event: { _tag: "PlantWatered" } };
    case "NoteShared":
      return undefined;
  }
};

/** A note's item: a text note opens the note, a drawing or a photo opens Moments. */
export const activityForNote = (note: Note): ActivityRow => ({
  id: decodeId(`note:${note.id}`),
  at: note.sentAt,
  doer: member(note.author),
  event: { _tag: "NoteSent", note: note.id, kind: note._tag },
  target:
    note._tag === "Text"
      ? ActivityTarget.cases.Note.make({ note: note.id })
      : ActivityTarget.cases.Moments.make({ note: note.id }),
});

const shopItem = Schema.decodeSync(ActivityShopItemId);
const decodeOffer = Schema.decodeSync(ActivityOfferId);
const decodeCollection = Schema.decodeSync(ActivityCollectionId);

type PurchasedOutput = typeof RoomOutput.cases.Purchased.Type;

/** A buy's item, under its spend's id. Tapping it opens the set bought, else the first item. */
const purchaseRow = ({ id, by, at, items, offer, coins }: PurchasedOutput): ActivityRow => {
  const bought = items.map((item) => shopItem(item));
  const [first] = bought;
  const target =
    offer !== undefined && !offer.startsWith("deal:")
      ? { target: ActivityTarget.cases.ShopOffer.make({ id: decodeOffer(offer) }) }
      : first === undefined
        ? {}
        : { target: ActivityTarget.cases.ShopItem.make({ id: first }) };
  return {
    id: decodeId(`spend:${id}`),
    at,
    doer: member(by),
    event: {
      _tag: "Purchased",
      ...(offer === undefined ? {} : { offer: decodeOffer(offer) }),
      items: bought,
      coins,
    },
    ...target,
  };
};

/**
 * The items an accepted decision adds, in the order of its outputs. `at` is the room's time for
 * outputs that carry none of their own (a save of the cat).
 */
export const activityOf = (
  outputs: ReadonlyArray<RoomOutput>,
  at: EpochMillis,
): ReadonlyArray<ActivityRow> =>
  outputs.flatMap((output): ReadonlyArray<ActivityRow> => {
    switch (output._tag) {
      case "NoteAppended":
        return [activityForNote(output.entry.note)];
      case "CatEntryAppended": {
        const row = activityForCatEntry(output.entry);
        return row === undefined ? [] : [row];
      }
      case "CatSaved": {
        const { cat, by, adopted } = output;
        // A burst of saves while typing is one item per minute, and the last name wins: rows
        // are written over by id.
        const minute = Math.floor(at / 60_000);
        return [
          {
            id: decodeId(`cat:${adopted ? "adopted" : `named-${minute}`}`),
            at,
            doer: member(by),
            event: adopted
              ? { _tag: "CatAdopted", name: cat.name }
              : { _tag: "CatRenamed", name: cat.name },
            target: ActivityTarget.cases.Cat.make({}),
          },
        ];
      }
      // One item per photo: the partner is the only one who can react, and a change moves it up.
      // Taking a reaction back leaves the item as it was.
      case "ReactionSet": {
        const { note, by, reaction, at: reactedAt } = output.reaction;
        return reaction === undefined
          ? []
          : [
              {
                id: decodeId(`reaction:${note}`),
                at: reactedAt,
                doer: member(by),
                event: { _tag: "Reacted", note, reaction },
                target: ActivityTarget.cases.Moments.make({ note }),
              },
            ];
      }
      case "Purchased":
        return [purchaseRow(output)];
      case "GiftOpened": {
        const { by, at: openedAt, day, reward } = output;
        return [
          {
            id: decodeId(`gift:${day}`),
            at: openedAt,
            doer: member(by),
            event: { _tag: "GiftClaimed", coins: reward._tag === "Coins" ? reward.coins : 0 },
            ...(reward._tag === "Item"
              ? { target: ActivityTarget.cases.ShopItem.make({ id: shopItem(reward.item) }) }
              : {}),
          },
        ];
      }
      case "BonusPaid": {
        const { by, at: paidAt, collection, coins } = output;
        return [
          {
            id: decodeId(`bonus:${collection}`),
            at: paidAt,
            doer: member(by),
            event: { _tag: "BonusEarned", collection: decodeCollection(collection), coins },
          },
        ];
      }
      // Written over by id, so the count and the latest text move up with each add.
      case "ListItemAdded": {
        const { list, kind, title, by, slot, at: addedAt, count, text } = output;
        return [
          {
            id: decodeId(`list:${list}:${listWindowOf(addedAt)}:${slot}`),
            at: addedAt,
            doer: member(by),
            event: { _tag: "ListItemAdded", list, kind, title, count, text },
            target: ActivityTarget.cases.List.make({ list }),
          },
        ];
      }
      // One item per member: a new check-in writes over their last one and moves it up.
      case "MoodSet": {
        const { user, mood, at: checkedAt } = output.checkIn;
        return [
          {
            id: decodeId(`mood:${user}`),
            at: checkedAt,
            doer: member(user),
            event: { _tag: "MoodShared", mood },
          },
        ];
      }
      // One item per milestone day: a later report of the same day writes over it.
      case "StreakChanged": {
        const { streak, by, at: reachedAt, reached } = output;
        return reached === undefined || streak.lastDay === undefined
          ? []
          : [
              {
                id: decodeId(`streak:${streak.lastDay}`),
                at: reachedAt,
                doer: member(by),
                event: { _tag: "StreakReached", days: reached },
              },
            ];
      }
      case "RoomOpened":
        return output.joined === undefined
          ? []
          : [
              {
                id: decodeId("pair:joined"),
                at: output.joined.at,
                doer: member(output.joined.user),
                event: { _tag: "PartnerJoined" },
              },
            ];
      case "ReactionRepeated":
      case "NoteRepeated":
      case "PresenceChanged":
      case "CatEntryRepeated":
      case "InksGranted":
      case "ItemsGranted":
      case "WishlistChanged":
      case "CoinsEntered":
      case "CoinsRepeated":
      case "ListSaved":
      case "ListDeleted":
      case "RiddleSaved":
        return [];
    }
  });

/** The row as `caller` sees it. */
export const itemFor = (row: ActivityRow, caller: UserId): ActivityItem => {
  const actor: ActivityActor =
    row.doer._tag === "Member" ? (row.doer.user === caller ? "Me" : "Partner") : row.doer._tag;
  return {
    id: row.id,
    at: row.at,
    actor,
    event: row.event,
    ...(row.target === undefined ? {} : { target: row.target }),
    cursor: cursorOf(row),
  };
};

/** Whether `caller` has an item to read in `row`: one they did not make themselves. */
export const countsAsUnread = (row: ActivityRow, caller: UserId): boolean =>
  row.doer._tag !== "Member" || row.doer.user !== caller;
