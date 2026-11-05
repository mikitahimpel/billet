import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Schema } from "effect";
import { expect, it } from "vitest";
import { LocalDay } from "@billet/contracts-domain/coins";
import type { EpochMillis } from "@billet/contracts-domain/ids";
import { dealsOn, featuredSetAt, giftItems, giftOn } from "@billet/contracts-domain/shop";

// The app draws the same deals, featured set and gift from the pair id and the local day. It reads
// this file in its tests and must answer each case the same way.
const path = join(dirname(fileURLToPath(import.meta.url)), "..", "shop-offers.json");

const seeds = ["pair-1", "0c9a8b7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d", "Paarë"];
const days = ["2024-01-01", "2025-02-28", "2026-11-05", "2026-11-09", "2026-12-31"].map((day) =>
  Schema.decodeSync(LocalDay)(day),
);
const noonOf = (day: LocalDay): EpochMillis => Date.parse(`${day}T12:00:00Z`);

const cases = seeds.flatMap((seed) =>
  days.map((day) => ({
    seed,
    day,
    deals: dealsOn(seed, day),
    featured: featuredSetAt(noonOf(day)).id,
    gift: giftOn(seed, day, new Set()),
    giftOwningGiftItems: giftOn(seed, day, new Set(giftItems)),
  })),
);

it("writes the offers the app must draw the same way", () => {
  const text = `${JSON.stringify({ cases }, null, 2)}\n`;
  writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
  expect(cases.some(({ gift }) => gift._tag === "Item")).toBe(true);
});
