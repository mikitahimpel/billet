import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import type { FlagRow } from "@billet/backend-metrics/funnel";
import { buildFunnel, FunnelDefinition, funnelEventNames } from "../src/admin-funnel.ts";
import type { BuildEventRow } from "../src/admin-retention.ts";

const today = "2026-11-04";
const at = (day: string, hour: number) =>
  Date.parse(`${day}T${String(hour).padStart(2, "0")}:00:00Z`);

/** One row: `who` did `name` on `day`, first at `first` o'clock and last at `last`. */
const row = (
  who: string,
  name: BuildEventRow["name"],
  day: string,
  first: number,
  last = first,
  pairId = `pair-${who}`,
): BuildEventRow => ({
  pairId,
  userId: who,
  name,
  day,
  count: 1,
  firstAt: at(day, first),
  lastAt: at(day, last),
});

/** `n` people who open the app and pet the cat an hour later the same day. */
const converters = (n: number, prefix: string, day = "2026-11-01") =>
  Array.from({ length: n }, (_, i) => [
    row(`${prefix}${i}`, "AppOpened", day, 9),
    row(`${prefix}${i}`, "CatPetted", day, 10 + (i % 3)),
  ]).flat();

const decode = Schema.decodeUnknownSync(FunnelDefinition);

describe("FunnelDefinition", () => {
  it("takes 2 to 6 different names from the closed list", () => {
    expect(() => decode({ steps: ["AppOpened"], window: "day", unit: "pair" })).toThrow();
    expect(() =>
      decode({ steps: ["AppOpened", "AppOpened"], window: "day", unit: "pair" }),
    ).toThrow();
    expect(() => decode({ steps: ["AppOpened", "Hacked"], window: "day", unit: "pair" })).toThrow();
    expect(() =>
      decode({ steps: ["AppOpened", "AccountDeleted"], window: "day", unit: "pair" }),
    ).toThrow();
    expect(() =>
      decode({ steps: funnelEventNames.slice(0, 7), window: "day", unit: "pair" }),
    ).toThrow();
    expect(decode({ steps: ["AppOpened", "NoteSent"], window: "7d", unit: "person" })).toEqual({
      steps: ["AppOpened", "NoteSent"],
      window: "7d",
      unit: "person",
    });
  });
});

describe("buildFunnel", () => {
  it("counts conversions in order, with the median time between steps", () => {
    const result = buildFunnel(converters(6, "u"), [], today, {
      steps: ["AppOpened", "CatPetted"],
      window: "day",
      unit: "person",
    });
    const [first, second] = result.groups[0]?.steps ?? [];
    expect(result.groups[0]?.entered).toBe(6);
    expect(first).toMatchObject({ count: 6, fromPrevious: null });
    expect(second).toMatchObject({ count: 6, fromFirst: 1 });
    expect(second?.fromPrevious?.share).toBe(1);
    // 1, 2, 3, 1, 2, 3 hours: the median is 2 hours.
    expect(second?.medianFromPrevious).toBe(2 * 3_600_000);
  });

  it("needs the next step at or after the one before, using the day's last moment when the first is earlier", () => {
    const rows = [
      ...converters(5, "u"),
      // Petted at 8 and again at 11, opened at 9: converts, at 11.
      row("late", "AppOpened", "2026-11-01", 9),
      row("late", "CatPetted", "2026-11-01", 8, 11),
      // Petted only at 8, before opening at 9: does not convert.
      row("early", "AppOpened", "2026-11-01", 9),
      row("early", "CatPetted", "2026-11-01", 8),
    ];
    const result = buildFunnel(rows, [], today, {
      steps: ["AppOpened", "CatPetted"],
      window: "day",
      unit: "person",
    });
    expect(result.groups[0]?.entered).toBe(7);
    expect(result.groups[0]?.steps[1]?.count).toBe(6);
  });

  it("keeps to the window: the same UTC day, 24 hours or 7 days after step 1", () => {
    const rows = [
      ...converters(5, "u"),
      row("next", "AppOpened", "2026-11-01", 23),
      row("next", "CatPetted", "2026-11-02", 1),
      row("week", "AppOpened", "2026-11-01", 9),
      row("week", "CatPetted", "2026-11-05", 9),
    ];
    const count = (window: "day" | "1d" | "7d") =>
      buildFunnel(rows, [], "2026-11-06", {
        steps: ["AppOpened", "CatPetted"],
        window,
        unit: "person",
      }).groups[0]?.steps[1]?.count;
    expect(count("day")).toBe(5);
    expect(count("1d")).toBe(6);
    expect(count("7d")).toBe(7);
  });

  it("counts a pair once, whichever partner did each step", () => {
    const rows = Array.from({ length: 5 }, (_, i) => [
      row(`a${i}`, "AppOpened", "2026-11-01", 9, 9, `p${i}`),
      row(`b${i}`, "NoteSent", "2026-11-01", 10, 10, `p${i}`),
      row(`b${i}`, "AppOpened", "2026-11-01", 9, 9, `p${i}`),
    ]).flat();
    const pair = buildFunnel(rows, [], today, {
      steps: ["AppOpened", "NoteSent"],
      window: "day",
      unit: "pair",
    });
    expect(pair.groups[0]).toMatchObject({ entered: 5 });
    expect(pair.groups[0]?.steps[1]?.count).toBe(5);
    const person = buildFunnel(rows, [], today, {
      steps: ["AppOpened", "NoteSent"],
      window: "day",
      unit: "person",
    });
    expect(person.groups[0]).toMatchObject({ entered: 10 });
    expect(person.groups[0]?.steps[1]?.count).toBe(5);
  });

  it("shows too few, with no number, for any count under 5, and only step 1 in the range", () => {
    // Six open the app; only four of them pet the cat. Four more did both long ago.
    const rows = [
      ...converters(4, "u"),
      row("v0", "AppOpened", "2026-11-01", 9),
      row("v1", "AppOpened", "2026-11-01", 9),
      ...converters(4, "old", "2026-09-01"),
    ];
    const definition = {
      steps: ["AppOpened", "CatPetted"],
      window: "day",
      unit: "person",
    } as const;
    const recent = buildFunnel(rows, [], today, definition, { range: "30" });
    expect(recent.from).toBe("2026-10-06");
    expect(recent.groups[0]?.entered).toBe(6);
    expect(recent.groups[0]?.steps[1]).toEqual({
      name: "CatPetted",
      count: null,
      fromPrevious: null,
      fromFirst: null,
      medianFromPrevious: null,
    });
    const all = buildFunnel(rows, [], today, definition, { range: "all" });
    expect(all.groups[0]?.entered).toBe(10);
    expect(all.groups[0]?.steps[1]?.count).toBe(8);
  });

  it("splits by variant, a person by the pair they joined", () => {
    const rows = [
      ...converters(5, "x"),
      ...converters(5, "y"),
      ...Array.from({ length: 10 }, (_, i) => {
        const who = i < 5 ? `x${i}` : `y${i - 5}`;
        return row(who, "PairClaimed", "2026-10-01", 9, 9, `pair-${who}`);
      }),
    ];
    const flags: Array<FlagRow> = Array.from({ length: 10 }, (_, i) => ({
      pairId: i < 5 ? `pair-x${i}` : `pair-y${i - 5}`,
      experimentKey: "home-layout",
      variant: i < 5 ? "classic" : "immersive",
    }));
    const result = buildFunnel(
      rows,
      flags,
      today,
      { steps: ["AppOpened", "CatPetted"], window: "day", unit: "person" },
      { split: "home-layout" },
    );
    expect(result.groups.map(({ variant, entered }) => [variant, entered])).toEqual([
      [null, 10],
      ["classic", 5],
      ["immersive", 5],
    ]);
    expect(result.experiments).toEqual(["home-layout"]);
  });
});
