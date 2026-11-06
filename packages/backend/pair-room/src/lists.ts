import type { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { Schema } from "effect";
import {
  type ListCommand,
  type ListId,
  type ListItem,
  type ListItemId,
  SharedList,
} from "@billet/contracts-domain/list";
import { RoomRejection } from "./room-decision.ts";

/**
 * Why a list change was refused. `NotOpen`: the room has no members yet, or the caller is not one
 * of them. The others: the list, or the item, is gone, so the change can never apply.
 */
export const ListRefusal = Schema.Literals(["NotOpen", "ListNotFound", "ListItemNotFound"]);
export type ListRefusal = typeof ListRefusal.Type;

/** What a list read or change answers: the pair's lists after it, or why it was refused. */
export const ListsResult = Schema.TaggedUnion({
  Done: { lists: Schema.Array(SharedList) },
  Refused: { reason: ListRefusal },
});
export type ListsResult = typeof ListsResult.Type;

/** The refusal a rejected list change answers with. */
export const listRefusalOf = (rejection: RoomRejection): ListRefusal =>
  rejection._tag === "ListNotFound" || rejection._tag === "ListItemNotFound"
    ? rejection._tag
    : "NotOpen";

/** The Inbox counts a partner's adds to one list within this window as one item. */
export const listActivityWindowMillis = 10 * 60_000;

/**
 * What one change does to the list it names. `added` and `ticked` are the item the change added or
 * ticked, for the Inbox and the coins.
 */
export type ListOutcome =
  | { readonly _tag: "Unchanged" }
  | {
      readonly _tag: "Saved";
      readonly list: SharedList;
      readonly added?: ListItem;
      readonly ticked?: ListItem;
    }
  | { readonly _tag: "Deleted"; readonly list: ListId }
  | { readonly _tag: "Refused"; readonly rejection: RoomRejection };

const unchanged: ListOutcome = { _tag: "Unchanged" };
const listNotFound: ListOutcome = {
  _tag: "Refused",
  rejection: RoomRejection.cases.ListNotFound.make({}),
};
const itemNotFound: ListOutcome = {
  _tag: "Refused",
  rejection: RoomRejection.cases.ListItemNotFound.make({}),
};

type Details = Pick<
  ListItem,
  "quantity" | "note" | "icon" | "aisle" | "media" | "country" | "place" | "visitedIn" | "moments"
>;

/** The details a change names, without the keys it leaves out. */
const detailsOf = (source: Details): Details => ({
  ...(source.quantity === undefined ? {} : { quantity: source.quantity }),
  ...(source.note === undefined ? {} : { note: source.note }),
  ...(source.icon === undefined ? {} : { icon: source.icon }),
  ...(source.aisle === undefined ? {} : { aisle: source.aisle }),
  ...(source.media === undefined ? {} : { media: source.media }),
  ...(source.country === undefined ? {} : { country: source.country }),
  ...(source.place === undefined ? {} : { place: source.place }),
  ...(source.visitedIn === undefined ? {} : { visitedIn: source.visitedIn }),
  ...(source.moments === undefined ? {} : { moments: source.moments }),
});

const withItem = (list: SharedList, item: ListItem): SharedList => ({
  ...list,
  items: list.items.map((existing) => (existing.id === item.id ? item : existing)),
});

/** Runs `change` on the item it names, refusing when the list or the item is gone. */
const onItem = (
  list: SharedList | undefined,
  id: ListItemId,
  change: (item: ListItem, list: SharedList) => ListOutcome,
): ListOutcome => {
  if (list === undefined) return listNotFound;
  const item = list.items.find((existing) => existing.id === id);
  return item === undefined ? itemNotFound : change(item, list);
};

/**
 * What `by` does to `list` (the stored list `change` names, absent when there is none) at `at`.
 * Pure. Making a list or an item under an id the room holds, or deleting one it doesn't, changes
 * nothing: a repeat after the key was forgotten, or both partners deleting at once.
 */
export const changeList = (
  list: SharedList | undefined,
  by: UserId,
  at: EpochMillis,
  change: ListCommand,
): ListOutcome => {
  switch (change._tag) {
    case "CreateList": {
      if (list !== undefined) return unchanged;
      const { kind, title, icon } = change;
      return { _tag: "Saved", list: { id: change.list, kind, title, icon, items: [] } };
    }
    case "RenameList": {
      if (list === undefined) return listNotFound;
      const { title, icon } = change;
      if (
        list.title === title &&
        list.icon.symbol === icon.symbol &&
        list.icon.tint === icon.tint
      ) {
        return unchanged;
      }
      return { _tag: "Saved", list: { ...list, title, icon } };
    }
    case "DeleteList":
      return list === undefined ? unchanged : { _tag: "Deleted", list: list.id };
    case "AddItem": {
      if (list === undefined) return listNotFound;
      if (list.items.some((item) => item.id === change.item)) return unchanged;
      const added: ListItem = {
        id: change.item,
        text: change.text,
        author: by,
        addedAt: at,
        ...detailsOf(change),
        wants: [],
      };
      return { _tag: "Saved", list: { ...list, items: [...list.items, added] }, added };
    }
    case "EditItem":
      return onItem(list, change.item, (item, of) => {
        const { id, author, addedAt, doneBy, doneAt, wants } = item;
        const edited: ListItem = {
          id,
          text: change.text,
          author,
          addedAt,
          ...(doneBy === undefined || doneAt === undefined ? {} : { doneBy, doneAt }),
          ...detailsOf(change),
          wants,
        };
        return { _tag: "Saved", list: withItem(of, edited) };
      });
    case "TickItem":
      return onItem(list, change.item, (item, of) => {
        if (item.doneAt !== undefined) return unchanged;
        const ticked: ListItem = { ...item, doneBy: by, doneAt: at };
        return { _tag: "Saved", list: withItem(of, ticked), ticked };
      });
    case "UntickItem":
      return onItem(list, change.item, (item, of) => {
        if (item.doneAt === undefined) return unchanged;
        const { id, text, author, addedAt, wants } = item;
        const open: ListItem = { id, text, author, addedAt, ...detailsOf(item), wants };
        return { _tag: "Saved", list: withItem(of, open) };
      });
    case "DeleteItem":
      if (list === undefined || !list.items.some((item) => item.id === change.item)) {
        return unchanged;
      }
      return {
        _tag: "Saved",
        list: { ...list, items: list.items.filter((item) => item.id !== change.item) },
      };
    case "WantItem":
      return onItem(list, change.item, (item, of) => {
        if (item.wants.includes(by) === change.wants) return unchanged;
        const wants = change.wants ? [...item.wants, by] : item.wants.filter((u) => u !== by);
        return { _tag: "Saved", list: withItem(of, { ...item, wants }) };
      });
  }
};

/** The window an add at `at` falls in. */
export const listWindowOf = (at: EpochMillis): number => Math.floor(at / listActivityWindowMillis);

/** How many items `by` added to `list` in the window `at` falls in, the one just added included. */
export const addsInWindow = (list: SharedList, by: UserId, at: EpochMillis): number => {
  const window = listWindowOf(at);
  return list.items.filter((item) => item.author === by && listWindowOf(item.addedAt) === window)
    .length;
};
