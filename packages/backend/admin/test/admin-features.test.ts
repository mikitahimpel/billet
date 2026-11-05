import { describe, expect, it } from "vitest";
import type { MetricEventName } from "@billet/contracts-domain/metrics";
import { addDays, type EventRow, type FlagRow } from "@billet/backend-metrics/funnel";
import { buildFeatureUsage, featureAreas } from "../src/admin-features.ts";

const today = "2026-11-04";

const row = (pairId: string, name: MetricEventName, day: string): EventRow => ({
  pairId,
  userId: `${pairId}-a`,
  name,
  day,
  count: 1,
  firstAt: Date.parse(`${day}T10:00:00Z`),
});

const find = (usage: ReturnType<typeof buildFeatureUsage>, event: string | null, area = "cat") =>
  usage.rows.find((entry) => entry.area === area && entry.event === event);

describe("buildFeatureUsage", () => {
  it("shares pairs active in each window, with an any-of row per area", () => {
    const events: Array<EventRow> = [];
    for (let i = 0; i < 20; i += 1) events.push(row(`p${i}`, "AppOpened", today));
    // 10 more pairs active only 20 days ago: in the 30-day window, not the 7-day one.
    for (let i = 20; i < 30; i += 1) events.push(row(`p${i}`, "AppOpened", addDays(today, -20)));
    // Petted: 6 this week, plus 4 of the older pairs back then. Fed: 5 this week, 3 of them petted.
    for (let i = 0; i < 6; i += 1) events.push(row(`p${i}`, "CatPetted", today));
    for (let i = 20; i < 24; i += 1) events.push(row(`p${i}`, "CatPetted", addDays(today, -20)));
    for (let i = 3; i < 8; i += 1) events.push(row(`p${i}`, "CatFed", addDays(today, -6)));
    // Before pairing, and older than 30 days: neither counts.
    events.push(row("", "CatPetted", today), row("p9", "CatPetted", addDays(today, -30)));

    const usage = buildFeatureUsage(events, [], today);
    expect(usage.from).toEqual({ d7: "2026-10-29", d30: "2026-10-06" });
    expect(usage.groups).toEqual([{ variant: null, active: { d7: 20, d30: 30 } }]);
    expect(find(usage, "CatPetted")?.cells[0]?.d7).toMatchObject({ count: 6, of: 20, share: 0.3 });
    expect(find(usage, "CatPetted")?.cells[0]?.d30).toMatchObject({ count: 10, of: 30 });
    expect(find(usage, "CatFed")?.cells[0]?.d7?.count).toBe(5);
    // Any cat: p0..p7 this week.
    expect(find(usage, null)?.cells[0]?.d7).toMatchObject({ count: 8, of: 20 });
    // Under 5 pairs: too few, never the number.
    expect(find(usage, "CatPlayed")?.cells[0]).toEqual({ d7: null, d30: null });
  });

  it("splits by variant, and hides a variant under 5 active pairs", () => {
    const events: Array<EventRow> = [];
    const flags: Array<FlagRow> = [];
    for (let i = 0; i < 14; i += 1) {
      events.push(row(`p${i}`, "AppOpened", today), row(`p${i}`, "ShopOpened", today));
      const variant = i < 10 ? "a" : "b";
      flags.push({ pairId: `p${i}`, experimentKey: "home-layout", variant });
    }
    const usage = buildFeatureUsage(events, flags, today, { split: "home-layout" });
    expect(usage.groups.map(({ variant, active }) => [variant, active.d7])).toEqual([
      [null, 14],
      ["a", 10],
      ["b", null],
    ]);
    expect(find(usage, "ShopOpened", "shop")?.cells.map(({ d7 }) => d7?.count ?? null)).toEqual([
      14,
      10,
      null,
    ]);
    expect(usage.experiments).toEqual(["home-layout"]);
  });

  it("lists only product events from the closed list", () => {
    const names = featureAreas.flatMap(({ events }) => events);
    expect(new Set(names).size).toBe(names.length);
    expect(names).not.toContain("AppOpened");
    expect(names).not.toContain("NoteSent");
  });
});
