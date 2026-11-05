import { Schema } from "effect";
import type { EpochMillis } from "./ids.ts";
import { KnownInkId } from "./inks.ts";

const slug = Schema.String.check(
  Schema.isPattern(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/),
  Schema.isMaxLength(40),
);

/** Names one piece of furniture or decor for the cat's room, such as `lamp`. Never reused. */
export const RoomItemId = slug.pipe(Schema.brand("RoomItemId"));
export type RoomItemId = typeof RoomItemId.Type;

/** Names a set of pieces sold together: a bundle or a week's featured set. Never reused. */
export const PieceSetId = slug.pipe(Schema.brand("PieceSetId"));
export type PieceSetId = typeof PieceSetId.Type;

/** One piece the shop sells. The app keeps its own name, art and copy for the id. */
export interface RoomItem {
  readonly id: RoomItemId;
  /** In coins. */
  readonly price: number;
}

/** Pieces sold together for `share` of the sum of the ones the pair does not own yet. */
export interface PieceSet {
  readonly id: PieceSetId;
  readonly items: ReadonlyArray<RoomItemId>;
  readonly share: number;
}

const decodeItemId = Schema.decodeSync(RoomItemId);
const decodeSetId = Schema.decodeSync(PieceSetId);

const item = (id: string, price: number): RoomItem => ({ id: decodeItemId(id), price });

const set = (id: string, items: ReadonlyArray<string>, share: number): PieceSet => ({
  id: decodeSetId(id),
  items: items.map((id) => decodeItemId(id)),
  share,
});

/**
 * Every piece for the cat's room. Pieces belong to the pair: one partner's purchase is both
 * partners'. This list is canonical, the app mirrors it, and an id stays here once it has been
 * sold. Prices are placeholders until the owner sets them.
 */
export const roomItems: ReadonlyArray<RoomItem> = [
  item("armchair", 320),
  item("lamp", 140),
  item("monstera", 90),
  item("bookcase", 260),
  item("rug", 180),
  item("yarn", 60),
  item("mouse", 45),
  item("tower", 540),
  item("print", 120),
  item("teatable", 210),
  item("donutbed", 380),
  item("lantern", 150),
];

/** The pieces every room starts with. They are never bought and never listed as bought. */
export const starterItems: ReadonlyArray<RoomItemId> = [decodeItemId("lamp"), decodeItemId("rug")];

/** Bundles stay in the shop all year. */
export const bundles: ReadonlyArray<PieceSet> = [
  set("mochi-playday", ["yarn", "mouse", "tower"], 0.7),
  set("reading-nook", ["bookcase", "armchair", "lamp"], 0.75),
  set("window-glow", ["lantern", "monstera", "print"], 0.75),
];

/** The featured sets, one a week in turn, at half the sum of their pieces. */
export const featuredSets: ReadonlyArray<PieceSet> = [
  set("rainy-evening", ["lamp", "armchair", "print"], 0.5),
  set("nap-time", ["donutbed", "rug", "lamp"], 0.5),
  set("tea-for-two", ["teatable", "monstera", "lantern"], 0.5),
];

/** A treat for the cat: spent at once, so the pair never owns one. */
export const treatPrice = 10;

export const roomItemOf = (id: string): RoomItem | undefined =>
  roomItems.find((entry) => entry.id === id);

export const pieceSetOf = (id: string): PieceSet | undefined =>
  [...bundles, ...featuredSets].find((entry) => entry.id === id);

export const KnownRoomItemId = RoomItemId.check(
  Schema.makeFilter((id) => roomItemOf(id) !== undefined || `expected a piece the catalog sells`),
);

export const KnownPieceSetId = PieceSetId.check(
  Schema.makeFilter((id) => pieceSetOf(id) !== undefined || `expected a set the catalog sells`),
);

const dayMillis = 86_400_000;
/** Monday 2024-01-01, the first day of week 0. */
const firstMonday = Date.UTC(2024, 0, 1);

/**
 * The featured set of the week `at` falls in, counted from Monday 2024-01-01, so the set changes
 * on Mondays. `utcOffsetSeconds` moves the week to the couple's own midnight.
 */
export const featuredSetAt = (at: EpochMillis, utcOffsetSeconds = 0): PieceSet => {
  const days = Math.floor((at + utcOffsetSeconds * 1000 - firstMonday) / dayMillis);
  const week = Math.floor(Math.max(0, days) / 7);
  return featuredSets[week % featuredSets.length] as PieceSet;
};

/** Rounded to 5 coins, so a set price reads cleanly. Halves round up, as the app's do. */
export const roundToFive = (value: number): number => Math.round(value / 5) * 5;

/**
 * What the pair pays for a set: its share of the pieces it does not own yet, next to those
 * pieces' sum. Undefined once it owns them all.
 */
export const setPrice = (
  pieces: PieceSet,
  owned: ReadonlySet<string>,
): { readonly price: number; readonly sum: number } | undefined => {
  const missing = pieces.items.flatMap((id) => {
    const sold = roomItemOf(id);
    return sold === undefined || owned.has(id) ? [] : [sold];
  });
  if (missing.length === 0) return undefined;
  const sum = missing.reduce((total, piece) => total + piece.price, 0);
  return { price: roundToFive(sum * pieces.share), sum };
};

/** What one order in the shop buys: an ink, a piece, a set's missing pieces, or a treat. */
export const ShopOffer = Schema.TaggedUnion({
  Ink: { ink: KnownInkId },
  Item: { item: KnownRoomItemId },
  Set: { set: KnownPieceSetId },
  Treat: {},
});
export type ShopOffer = typeof ShopOffer.Type;
