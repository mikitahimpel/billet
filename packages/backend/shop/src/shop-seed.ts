import { inks } from "@billet/contracts-domain/inks";
import { roomItems } from "@billet/contracts-domain/shop";
import { ShopCatalogItem } from "@billet/contracts-domain/shop-catalog";
import { Schema } from "effect";

interface Shown {
  readonly name: string;
  readonly blurb: string;
  readonly mood?: string;
  readonly rarity: ShopCatalogItem["rarity"];
  readonly section: string;
  readonly plus?: true;
  readonly isNew?: true;
}

// What the app shows for each piece today (apps/ios/Nooki/Model/Shop.swift). `{cat}` is the cat's name.
const shown: Record<string, Shown> = {
  armchair: {
    name: "Cloud Armchair",
    blurb: "Big enough for two and a cat who insists.",
    mood: "Rested",
    rarity: "epic",
    section: "furniture",
    isNew: true,
  },
  lamp: {
    name: "Mushroom Lamp",
    blurb: "Warm glow for late-night talks.",
    mood: "Rested",
    rarity: "rare",
    section: "decor",
  },
  monstera: {
    name: "Monstera",
    blurb: "Grows a new leaf every week you visit.",
    rarity: "common",
    section: "decor",
  },
  bookcase: {
    name: "Little Bookcase",
    blurb: "Room for both your favourite stories.",
    rarity: "epic",
    section: "furniture",
  },
  rug: {
    name: "Woven Rug",
    blurb: "Soft rings in honey and blush.",
    rarity: "rare",
    section: "room",
  },
  yarn: {
    name: "Yarn Ball",
    blurb: "{cat}'s favourite thing to unravel.",
    mood: "Curious",
    rarity: "common",
    section: "mochi",
  },
  mouse: {
    name: "Toy Mouse",
    blurb: "Squeaks a little. {cat} pretends not to care.",
    mood: "Curious",
    rarity: "common",
    section: "mochi",
  },
  tower: {
    name: "Cat Tower",
    blurb: "Two floors, one nap spot at the very top.",
    mood: "Happy",
    rarity: "legendary",
    section: "mochi",
    plus: true,
  },
  print: {
    name: "Sunset Print",
    blurb: "The sky from your first evening walk.",
    rarity: "rare",
    section: "decor",
  },
  teatable: {
    name: "Tea Table",
    blurb: "Two cups, always.",
    rarity: "rare",
    section: "furniture",
    isNew: true,
  },
  donutbed: {
    name: "Donut Bed",
    blurb: "Sprinkles included, calories not.",
    mood: "Rested",
    rarity: "epic",
    section: "mochi",
  },
  lantern: {
    name: "Paper Lantern",
    blurb: "Hangs by the window and hums with light.",
    rarity: "legendary",
    section: "room",
    plus: true,
  },
};

// The daily-deals draw today: this pool in this order, each at its discount.
const dealPool = [
  ["teatable", 0.25],
  ["yarn", 0.3],
  ["lantern", 0.2],
  ["bookcase", 0.2],
  ["mouse", 0.3],
  ["lamp", 0.25],
  ["donutbed", 0.2],
  ["monstera", 0.3],
  ["print", 0.25],
] as const;

const decode = Schema.decodeUnknownSync(ShopCatalogItem);

/**
 * The shop as the app sold it before the catalog moved to D1: the same pieces, inks and prices.
 * The migration that creates the catalog inserts exactly these rows, and a test keeps the two
 * equal. Only the free ink is left out: it is never sold.
 */
export const seedItems: ReadonlyArray<ShopCatalogItem> = [
  ...roomItems.map((room, index) => {
    const info = shown[room.id];
    if (info === undefined) throw new Error(`no shop copy for ${room.id}`);
    const deal = dealPool.findIndex(([id]) => id === room.id);
    return decode({
      id: room.id,
      kind: info.section,
      name: info.name,
      blurb: info.blurb,
      ...(info.mood === undefined ? {} : { mood: info.mood }),
      rarity: info.rarity,
      price: room.price,
      ...(deal < 0 ? {} : { deal: { discount: dealPool[deal]?.[1], order: deal } }),
      section: info.section,
      sortOrder: (index + 1) * 10,
      ...(info.plus === true ? { plus: true } : {}),
      ...(info.isNew === true ? { isNew: true } : {}),
      asset: { _tag: "Bundled", id: room.id },
    });
  }),
  ...inks
    .filter((ink) => ink.price > 0)
    .map((ink, index) =>
      decode({
        id: ink.id,
        kind: "ink",
        name: ink.name,
        rarity: ink.price >= 120 ? "epic" : ink.price >= 90 ? "rare" : "common",
        price: ink.price,
        section: "inks",
        sortOrder: 1000 + (index + 1) * 10,
        asset: { _tag: "Bundled", id: ink.id },
      }),
    ),
];

/** When the migration wrote the seed, as `created_at` and `updated_at`. */
export const seedAt = 1_794_009_600_000;
export const seedBy = "migration";
