import { Schema } from "effect";
import { EpochMillis, IdempotencyKey, UserId } from "./ids.ts";

const uuid = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;

/** A shared list, named by the phone that made it. */
export const ListId = Schema.String.check(Schema.isPattern(uuid)).pipe(Schema.brand("ListId"));
export type ListId = typeof ListId.Type;

/** One item of a list, named by the phone that added it. */
export const ListItemId = Schema.String.check(Schema.isPattern(uuid)).pipe(
  Schema.brand("ListItemId"),
);
export type ListItemId = typeof ListItemId.Type;

/** `groceries` is a plain checklist; every other kind is a "we want to" list whose ticks earn. */
export const ListKind = Schema.Literals([
  "watch",
  "groceries",
  "travel",
  "food",
  "books",
  "bucket",
  "custom",
]);
export type ListKind = typeof ListKind.Type;

/** Whether ticking an item of this kind earns the pair coins. */
export const earnsOnTick = (kind: ListKind): boolean => {
  switch (kind) {
    case "groceries":
      return false;
    case "watch":
    case "travel":
    case "food":
    case "books":
    case "bucket":
    case "custom":
      return true;
  }
};

/** 1 to `max` UTF-16 units, not only whitespace. The app trims before it sends. */
const Line = (max: number) =>
  Schema.String.check(
    Schema.makeFilter(
      (text) =>
        (text.trim().length > 0 && text.length <= max) ||
        `expected 1 to ${max} characters, not only whitespace`,
    ),
  );

const Text = (max: number) => Schema.String.check(Schema.isMaxLength(max));

/** A lowercase name the phone draws from, such as an icon (`apple`) or a store aisle (`dairy`). */
const Slug = Schema.String.check(Schema.isPattern(/^[a-z0-9.-]{1,40}$/));

export const ListTitle = Line(60);
export type ListTitle = typeof ListTitle.Type;

export const ListItemText = Line(300);
export type ListItemText = typeof ListItemText.Type;

export const ListTint = Schema.Literals(["honey", "blush", "sky", "sage", "lilac", "sun", "coral"]);
export type ListTint = typeof ListTint.Type;

/** An SF Symbol on a tinted tile. */
export const ListIcon = Schema.Struct({
  symbol: Schema.String.check(Schema.isPattern(/^[a-z0-9.]{1,64}$/)),
  tint: ListTint,
});
export type ListIcon = typeof ListIcon.Type;

export const MediaKind = Schema.Literals(["movie", "tv"]);
export type MediaKind = typeof MediaKind.Type;

export const TmdbId = Schema.Int.check(Schema.isGreaterThanOrEqualTo(1));

/** A TMDB image file such as `/qJeU7KM4nT2C1WpOrwPcSDGFUWE.jpg`, served by `image.tmdb.org`. */
export const TmdbImagePath = Schema.String.check(
  Schema.isPattern(/^\/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|svg|webp)$/),
);
export type TmdbImagePath = typeof TmdbImagePath.Type;

/** The year a film came out or a show began. */
export const ReleaseYear = Schema.Int.check(Schema.isBetween({ minimum: 1870, maximum: 2200 }));

/**
 * A film or a show on TMDB. Its ids are counted per kind, so the kind is part of the id. The item's
 * text is its title; `year` and `posterPath` are what the grid draws without asking TMDB. Every
 * other detail is fetched when shown, never kept in the room.
 */
export const ListMedia = Schema.Struct({
  kind: MediaKind,
  tmdb: TmdbId,
  year: Schema.optionalKey(ReleaseYear),
  posterPath: Schema.optionalKey(TmdbImagePath),
});
export type ListMedia = typeof ListMedia.Type;

/** ISO 3166-1 alpha-2, such as `PT`. */
export const CountryCode = Schema.String.check(Schema.isPattern(/^[A-Z]{2}$/));
export type CountryCode = typeof CountryCode.Type;

/** A month such as `2026-10`. */
export const YearMonth = Schema.String.check(Schema.isPattern(/^\d{4}-(0[1-9]|1[0-2])$/));
export type YearMonth = typeof YearMonth.Type;

/** A shared moment, named by the idempotency key of the photo note that brought it. */
export const MomentId = Schema.String.check(Schema.isPattern(uuid));
export type MomentId = typeof MomentId.Type;

/**
 * What a partner says about an item, apart from its tick. Every field may be left out; `icon` and
 * `aisle` override what the phone would pick from the text. On a travel list an item with a
 * `country` is that country, or with `place` a city or place in it; `visitedIn` and `moments` are
 * the month the pair went and the photos from it.
 */
export const ListItemDetails = {
  quantity: Schema.optionalKey(Text(40)),
  note: Schema.optionalKey(Text(500)),
  icon: Schema.optionalKey(Slug),
  aisle: Schema.optionalKey(Slug),
  media: Schema.optionalKey(ListMedia),
  country: Schema.optionalKey(CountryCode),
  place: Schema.optionalKey(Schema.Boolean),
  visitedIn: Schema.optionalKey(YearMonth),
  moments: Schema.optionalKey(Schema.Array(MomentId).check(Schema.isMaxLength(10))),
};

/**
 * One item. `author` and `addedAt` are the room's, from the add; `doneBy` and `doneAt` are both
 * present once it is ticked. `wants` are the members who want it, in the order they said so.
 */
export const ListItem = Schema.Struct({
  id: ListItemId,
  text: ListItemText,
  author: UserId,
  addedAt: EpochMillis,
  doneBy: Schema.optionalKey(UserId),
  doneAt: Schema.optionalKey(EpochMillis),
  ...ListItemDetails,
  wants: Schema.Array(UserId),
});
export type ListItem = typeof ListItem.Type;

/** A list both partners see and edit. `items` are in the order they were added, oldest first. */
export const SharedList = Schema.Struct({
  id: ListId,
  kind: ListKind,
  title: ListTitle,
  icon: ListIcon,
  items: Schema.Array(ListItem),
});
export type SharedList = typeof SharedList.Type;

/**
 * A change either partner makes. `key` is the phone's, once per change: the room applies a key
 * once, so a retry changes nothing. An edit sets every detail, so one left out is cleared.
 */
export const ListCommand = Schema.TaggedUnion({
  CreateList: {
    key: IdempotencyKey,
    list: ListId,
    kind: ListKind,
    title: ListTitle,
    icon: ListIcon,
  },
  RenameList: { key: IdempotencyKey, list: ListId, title: ListTitle, icon: ListIcon },
  DeleteList: { key: IdempotencyKey, list: ListId },
  AddItem: {
    key: IdempotencyKey,
    list: ListId,
    item: ListItemId,
    text: ListItemText,
    ...ListItemDetails,
  },
  EditItem: {
    key: IdempotencyKey,
    list: ListId,
    item: ListItemId,
    text: ListItemText,
    ...ListItemDetails,
  },
  /** The first tick wins: ticking an item already ticked changes nothing. */
  TickItem: { key: IdempotencyKey, list: ListId, item: ListItemId },
  UntickItem: { key: IdempotencyKey, list: ListId, item: ListItemId },
  DeleteItem: { key: IdempotencyKey, list: ListId, item: ListItemId },
  /** The caller wants the item, or no longer does. */
  WantItem: { key: IdempotencyKey, list: ListId, item: ListItemId, wants: Schema.Boolean },
});
export type ListCommand = typeof ListCommand.Type;
