import { describe, expect, it } from "vitest";
import type { FlagRow } from "@billet/backend-metrics/funnel";
import {
  type BuildEventRow,
  buildRetentionGrid,
  minimumGroup,
  type RetentionCell,
  weekOf,
} from "../src/admin-retention.ts";
import { makeSeed } from "../src/seed-data.ts";

const today = "2026-11-04";

/** A pair formed on `day` whose partners were active on the given days after it. */
const pair = (
  id: string,
  day: string,
  active: { readonly a?: ReadonlyArray<number>; readonly b?: ReadonlyArray<number> },
  appVersion = "1.2.0+14",
): Array<BuildEventRow> => {
  const at = Date.parse(`${day}T12:00:00Z`);
  const rows: Array<BuildEventRow> = [
    { pairId: id, userId: `${id}-a`, name: "PairClaimed", day, count: 1, firstAt: at },
    { pairId: id, userId: `${id}-b`, name: "PairClaimed", day, count: 1, firstAt: at },
    { pairId: id, userId: `${id}-a`, name: "AppOpened", day, count: 1, firstAt: at, appVersion },
  ];
  for (const [who, days] of Object.entries(active)) {
    for (const n of days ?? []) {
      const on = new Date(Date.parse(`${day}T00:00:00Z`) + n * 86_400_000)
        .toISOString()
        .slice(0, 10);
      rows.push({
        pairId: id,
        userId: `${id}-${who}`,
        name: "NoteSent",
        day: on,
        count: 1,
        firstAt: at + n * 86_400_000,
      });
    }
  }
  return rows;
};

const cellsIn = (grid: ReturnType<typeof buildRetentionGrid>): Array<RetentionCell> =>
  grid.rows.flatMap((row) => [...row.cells.both, ...row.cells.either, ...row.cells.bothNote]);

describe("buildRetentionGrid", () => {
  it("weeks start on Monday, UTC", () => {
    expect(weekOf("2026-11-04")).toBe("2026-11-02");
    expect(weekOf("2026-11-02")).toBe("2026-11-02");
    expect(weekOf("2026-11-01")).toBe("2026-10-26");
  });

  it("counts both, either and both-sent-a-note, greys days not reached and hides small groups", () => {
    // Six pairs formed on Monday 2026-10-26, nine days before today.
    const events = [
      ...pair("p1", "2026-10-26", { a: [1, 7], b: [1, 7] }),
      ...pair("p2", "2026-10-26", { a: [1], b: [3] }),
      ...pair("p3", "2026-10-26", { a: [1, 3, 7] }),
      ...pair("p4", "2026-10-26", {}),
      ...pair("p5", "2026-10-26", { b: [7] }),
      ...pair("p6", "2026-10-26", { a: [1], b: [1] }),
      // Three pairs the week after: too few for any number.
      ...pair("q1", "2026-11-02", { a: [1], b: [1] }),
      ...pair("q2", "2026-11-02", {}),
      ...pair("q3", "2026-11-03", {}),
    ];
    const grid = buildRetentionGrid(events, [], today);
    const [newest, older, all] = grid.rows;
    expect(grid.rows.map(({ week }) => week)).toEqual(["2026-11-02", "2026-10-26", "all"]);

    expect(newest?.pairs).toBeNull();
    expect(newest?.cells.both.slice(0, 2)).toEqual([{ state: "too-few" }, { state: "pending" }]);

    expect(older?.pairs).toBe(6);
    const day = (mode: "both" | "either" | "bothNote", column: number) => {
      const cell = older?.cells[mode][column];
      return cell?.state === "value" ? [cell.count, cell.of] : cell?.state;
    };
    expect(day("both", 0)).toEqual([2, 6]); // p1, p6
    expect(day("either", 0)).toEqual([4, 6]); // p1, p2, p3, p6
    expect(day("bothNote", 2)).toEqual([1, 6]); // day 7: p1
    expect(day("either", 2)).toEqual([3, 6]); // day 7: p1, p3, p5
    expect(day("both", 3)).toBe("pending"); // day 14 not reached

    // The all-weeks row: every pair has reached day 1 (q3 formed yesterday); day 7 only the six.
    expect(all?.cells.both[0]).toMatchObject({ state: "value", count: 3, of: 9, partial: false });
    expect(all?.cells.either[2]).toMatchObject({ state: "value", count: 3, of: 6, partial: true });
  });

  it("filters by variant and by the build the pair formed on", () => {
    const events = [
      ...Array.from({ length: 5 }, (_, i) => pair(`a${i}`, "2026-10-01", { a: [1] }, "1.1.0+12")),
      ...Array.from({ length: 5 }, (_, i) => pair(`b${i}`, "2026-10-01", { a: [1] }, "1.2.0+14")),
    ].flat();
    const flags: Array<FlagRow> = Array.from({ length: 5 }, (_, i) => ({
      pairId: `a${i}`,
      experimentKey: "home-layout",
      variant: "immersive",
    }));
    expect(buildRetentionGrid(events, flags, today).rows.at(-1)?.pairs).toBe(10);
    const immersive = buildRetentionGrid(events, flags, today, {
      variant: { key: "home-layout", variant: "immersive" },
    });
    expect(immersive.rows.at(-1)?.pairs).toBe(5);
    expect(immersive.options.variants).toEqual([{ key: "home-layout", variant: "immersive" }]);
    const newer = buildRetentionGrid(events, flags, today, { appVersion: "1.2.0+14" });
    expect(newer.rows.at(-1)?.pairs).toBe(5);
    expect(newer.options.appVersions).toEqual(["1.1.0+12", "1.2.0+14"]);
    const both = buildRetentionGrid(events, flags, today, {
      variant: { key: "home-layout", variant: "immersive" },
      appVersion: "1.2.0+14",
    });
    expect(both.rows).toEqual([expect.objectContaining({ week: "all", pairs: null })]);
  });

  it("never shows a number resting on fewer than five pairs, under any filter of the seed", () => {
    const seed = makeSeed({ today });
    const unfiltered = buildRetentionGrid(seed.events, seed.flags, today);
    const filters = [
      {},
      ...unfiltered.options.variants.map((variant) => ({ variant })),
      ...unfiltered.options.appVersions.map((appVersion) => ({ appVersion })),
    ];
    for (const filter of filters) {
      const grid = buildRetentionGrid(seed.events, seed.flags, today, filter);
      for (const row of grid.rows)
        expect(row.pairs === null || row.pairs >= minimumGroup).toBe(true);
      for (const cell of cellsIn(grid)) {
        if (cell.state === "value") expect(cell.of).toBeGreaterThanOrEqual(minimumGroup);
      }
    }
  });
});
