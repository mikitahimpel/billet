import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Schema } from "effect";
import { expect, it } from "vitest";
import { LocalDay, rewardForEarn, type EarnEvent } from "@billet/contracts-domain/coins";
import { collections } from "@billet/contracts-domain/shop";

// The app promises these amounts on its labels. It reads this file in its tests and must show the
// same numbers the server pays.
const path = join(dirname(fileURLToPath(import.meta.url)), "..", "rewards.json");

const day = Schema.decodeSync(LocalDay)("2026-01-01");
const coinsFor = (event: EarnEvent): number => rewardForEarn(event).coins;

const rewards = {
  earn: {
    moment: coinsFor({ _tag: "MomentAdded", moment: "m" } as EarnEvent),
    note: coinsFor({ _tag: "NoteAdded", note: "n" } as EarnEvent),
    dateMatched: coinsFor({ _tag: "DateMatched", idea: "i" } as EarnEvent),
    dateRated: coinsFor({ _tag: "DateRated", plan: "p" } as EarnEvent),
    wishReceived: coinsFor({ _tag: "WishReceived", wish: "w" } as EarnEvent),
    listTicked: coinsFor({ _tag: "ListTicked", item: "l" } as EarnEvent),
    roundPlayed: coinsFor({ _tag: "RoundPlayed", round: day } as EarnEvent),
    guessHit: coinsFor({ _tag: "GuessHit", round: day, question: 1 } as EarnEvent),
  },
  collections: Object.fromEntries(collections.map(({ id, bonus }) => [id, bonus])),
};

it("writes the rewards the app must show the same way", () => {
  const text = `${JSON.stringify(rewards, null, 2)}\n`;
  writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
  expect(Object.keys(rewards.collections)).not.toHaveLength(0);
});
