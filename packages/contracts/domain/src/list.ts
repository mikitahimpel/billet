import { Schema } from "effect";
import { EpochMillis, IdempotencyKey, UserId } from "./ids.ts";

const uuid = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;

/** Named by the phone that made it. */
export const ListId = Schema.String.check(Schema.isPattern(uuid)).pipe(Schema.brand("ListId"));
export type ListId = typeof ListId.Type;

/** Named by the phone that added it. */
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

/** Served by `image.tmdb.org`. */
export const TmdbImagePath = Schema.String.check(
  Schema.isPattern(/^\/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|svg|webp)$/),
);
export type TmdbImagePath = typeof TmdbImagePath.Type;

export const ReleaseYear = Schema.Int.check(Schema.isBetween({ minimum: 1870, maximum: 2200 }));

/** TMDB ids are counted per kind, so `kind` is part of the id. Details beyond `year` and
 * `posterPath` are fetched when shown, never kept in the room. */
export const ListMedia = Schema.Struct({
  kind: MediaKind,
  tmdb: TmdbId,
  year: Schema.optionalKey(ReleaseYear),
  posterPath: Schema.optionalKey(TmdbImagePath),
});
export type ListMedia = typeof ListMedia.Type;

/** ISO 3166-1 alpha-2. */
export const CountryCode = Schema.String.check(Schema.isPattern(/^[A-Z]{2}$/));
export type CountryCode = typeof CountryCode.Type;

export const YearMonth = Schema.String.check(Schema.isPattern(/^\d{4}-(0[1-9]|1[0-2])$/));
export type YearMonth = typeof YearMonth.Type;

/** The idempotency key of the photo note that brought the moment. */
export const MomentId = Schema.String.check(Schema.isPattern(uuid));
export type MomentId = typeof MomentId.Type;

/** `icon` and `aisle` override what the phone would pick from the text. On a travel list, an item
 * with `country` is that country, or with `place` a city or place in it. */
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

/** `author` and `addedAt` are set by the room; `doneBy` and `doneAt` both present once ticked.
 * `wants` is in the order members said so. */
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

/** `items` oldest first. */
export const SharedList = Schema.Struct({
  id: ListId,
  kind: ListKind,
  title: ListTitle,
  icon: ListIcon,
  items: Schema.Array(ListItem),
});
export type SharedList = typeof SharedList.Type;

/** The room applies a `key` once, so a retry changes nothing. An edit sets every detail, so one
 * left out is cleared. */
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
  WantItem: { key: IdempotencyKey, list: ListId, item: ListItemId, wants: Schema.Boolean },
});
export type ListCommand = typeof ListCommand.Type;
