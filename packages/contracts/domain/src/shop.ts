import { Schema } from "effect";
import type { LocalDay } from "./coins.ts";
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

/** Names pieces that earn a coin bonus once the pair owns them all, such as `cozy-autumn`. */
export const CollectionId = slug.pipe(Schema.brand("CollectionId"));
export type CollectionId = typeof CollectionId.Type;

export interface PieceCollection {
  readonly id: CollectionId;
  readonly items: ReadonlyArray<RoomItemId>;
  /** Coins paid once, when the pair first owns every piece. */
  readonly bonus: number;
}

const decodeCollectionId = Schema.decodeSync(CollectionId);

const collection = (id: string, items: ReadonlyArray<string>, bonus: number): PieceCollection => ({
  id: decodeCollectionId(id),
  items: items.map((id) => decodeItemId(id)),
  bonus,
});

/** Collections count the starter pieces as owned. Bonuses are placeholders until the owner sets them. */
export const collections: ReadonlyArray<PieceCollection> = [
  collection(
    "cozy-autumn",
    ["lamp", "lantern", "armchair", "rug", "teatable", "print", "monstera"],
    150,
  ),
  collection("mochis-corner", ["yarn", "mouse", "tower", "donutbed"], 100),
];

export const collectionOf = (id: string): PieceCollection | undefined =>
  collections.find((entry) => entry.id === id);

/** The coins every pair is given once, when its room opens. A placeholder until the owner sets it. */
export const welcomeCoins = 560;

/** How much a treat feeds the cat, in grams. */
export const treatGrams = 20;

// Rotations. Each is a pure function of a seed and the pair's local day, so both phones and the
// server agree without asking each other. The seed is the pair id: the app seeds the same
// functions with it. The hash and the generator are 64-bit, as in the app's `ShopOffers`.

const mask64 = (1n << 64n) - 1n;

// The contracts run without the DOM or Node, so no `TextEncoder`.
const utf8 = (text: string): ReadonlyArray<number> =>
  [...text].flatMap((char) => {
    const code = char.codePointAt(0) ?? 0;
    if (code < 0x80) return [code];
    if (code < 0x800) return [0xc0 | (code >> 6), 0x80 | (code & 0x3f)];
    if (code < 0x10000) {
      return [0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f)];
    }
    return [
      0xf0 | (code >> 18),
      0x80 | ((code >> 12) & 0x3f),
      0x80 | ((code >> 6) & 0x3f),
      0x80 | (code & 0x3f),
    ];
  });

/** FNV-1a over the UTF-8 bytes. */
export const fnv1a = (text: string): bigint => {
  let hash = 0xcbf2_9ce4_8422_2325n;
  for (const byte of utf8(text)) {
    hash = ((hash ^ BigInt(byte)) * 0x100_0000_01b3n) & mask64;
  }
  return hash;
};

/** SplitMix64: each call returns the next 64-bit value. */
export const splitMix64 = (seed: bigint): (() => bigint) => {
  let state = seed & mask64;
  return () => {
    state = (state + 0x9e37_79b9_7f4a_7c15n) & mask64;
    let z = state;
    z = ((z ^ (z >> 30n)) * 0xbf58_476d_1ce4_e5b9n) & mask64;
    z = ((z ^ (z >> 27n)) * 0x94d0_49bb_1331_11ebn) & mask64;
    return z ^ (z >> 31n);
  };
};

/** The app's key for a day: no zero padding, such as `2026-11-5`. */
const dayKey = (day: LocalDay): string =>
  day
    .split("-")
    .map((part) => String(Number(part)))
    .join("-");

/** One of the day's discounted pieces. `discount` 0.25 is 25% off. */
export interface Deal {
  readonly item: RoomItemId;
  readonly discount: number;
  readonly price: number;
}

/** How many deals a day has. */
export const dealCount = 4;

const dealOf = (item: string, discount: number) => ({ item: decodeItemId(item), discount });

/** Pieces that can be a deal, with their discount; each day draws `dealCount` of them. */
export const dealPool: ReadonlyArray<{ readonly item: RoomItemId; readonly discount: number }> = [
  dealOf("teatable", 0.25),
  dealOf("yarn", 0.3),
  dealOf("lantern", 0.2),
  dealOf("bookcase", 0.2),
  dealOf("mouse", 0.3),
  dealOf("lamp", 0.25),
  dealOf("donutbed", 0.2),
  dealOf("monstera", 0.3),
  dealOf("print", 0.25),
];

/** The day's deals, in the order they were drawn. */
export const dealsOn = (seed: string, day: LocalDay): ReadonlyArray<Deal> => {
  const next = splitMix64(fnv1a(`${seed}|deals|${dayKey(day)}`));
  const pool = [...dealPool];
  const picked: Array<Deal> = [];
  while (picked.length < dealCount && pool.length > 0) {
    const [entry] = pool.splice(Number(next() % BigInt(pool.length)), 1);
    if (entry === undefined) break;
    const price = roomItemOf(entry.item)?.price ?? 0;
    picked.push({ ...entry, price: roundToFive(price * (1 - entry.discount)) });
  }
  return picked;
};

/** What `item` costs on `day`: the deal price when it is one of the day's deals. */
export const itemPriceOn = (
  item: RoomItem,
  seed: string,
  day: LocalDay,
): { readonly price: number; readonly deal?: Deal } => {
  const deal = dealsOn(seed, day).find((entry) => entry.item === item.id);
  return deal === undefined ? { price: item.price } : { price: deal.price, deal };
};

/** The free gift for a day: coins, or a piece the pair doesn't own yet. */
export const GiftReward = Schema.TaggedUnion({
  Coins: { coins: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)) },
  Item: { item: RoomItemId },
});
export type GiftReward = typeof GiftReward.Type;

/** Gift coins are one of these; one day in four it is one of `giftItems` instead. */
export const giftCoins: ReadonlyArray<number> = [20, 30, 40];
export const giftItems: ReadonlyArray<RoomItemId> = ["mouse", "yarn", "monstera"].map((id) =>
  decodeItemId(id),
);

/** The gift for `day`. A piece the pair already owns turns into coins. */
export const giftOn = (seed: string, day: LocalDay, owned: ReadonlySet<string>): GiftReward => {
  const next = splitMix64(fnv1a(`${seed}|gift|${dayKey(day)}`));
  const roll = next();
  if (roll % 4n === 0n) {
    const item = giftItems[Number((roll / 4n) % BigInt(giftItems.length))];
    if (item !== undefined && !owned.has(item)) return { _tag: "Item", item };
  }
  return { _tag: "Coins", coins: giftCoins[Number(next() % BigInt(giftCoins.length))] ?? 0 };
};
