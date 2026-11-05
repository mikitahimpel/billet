import { describe, expect, it } from "vitest";
import type { MetricEventName } from "@billet/contracts-domain/metrics";
import { addDays, type FlagRow } from "@billet/backend-metrics/funnel";
import { buildExperimentMetrics } from "../src/admin-experiment-metrics.ts";
import type { BuildEventRow } from "../src/admin-retention.ts";

const today = "2026-11-04";
const formed = "2026-10-01";

const row = (
  pairId: string,
  userId: string,
  name: MetricEventName,
  day: string,
  count = 1,
): BuildEventRow => ({
  pairId,
  userId,
  name,
  day,
  count,
  firstAt: Date.parse(`${day}T10:00:00Z`),
});

interface PairPlan {
  readonly opensPerDay?: number;
  readonly notesPerDay?: number;
  readonly bothDay7?: boolean;
  readonly bothWidget?: boolean;
  readonly formedDay?: string;
}

/** A pair formed on `formedDay` whose two partners each do the plan on days 0 to 7. */
const pair = (id: string, plan: PairPlan = {}): Array<BuildEventRow> => {
  const day0 = plan.formedDay ?? formed;
  const members = [`${id}-a`, `${id}-b`];
  const rows = members.map((user) => row(id, user, "PairClaimed", day0));
  for (let offset = 0; offset <= 7; offset += 1) {
    const day = addDays(day0, offset);
    const opens = plan.opensPerDay ?? 0;
    if (opens > 0 && offset < 7) rows.push(row(id, `${id}-a`, "AppOpened", day, opens));
    const notes = plan.notesPerDay ?? 0;
    if (notes > 0 && offset < 7) rows.push(row(id, `${id}-b`, "NoteSent", day, notes));
  }
  if (plan.bothDay7 === true) {
    for (const user of members) rows.push(row(id, user, "AppOpened", addDays(day0, 7)));
  }
  if (plan.bothWidget === true) {
    for (const user of members) rows.push(row(id, user, "WidgetAdded", addDays(day0, 2)));
  }
  return rows;
};

const flag = (pairId: string, variant: string): FlagRow => ({
  pairId,
  experimentKey: "home-layout",
  variant,
});

const metric = (result: ReturnType<typeof buildExperimentMetrics>, id: string) =>
  result[0]?.metrics.find((entry) => entry.id === id);

describe("buildExperimentMetrics", () => {
  it("reads each metric over the first week, per variant, against the default", () => {
    const events: Array<BuildEventRow> = [];
    const flags: Array<FlagRow> = [];
    for (let i = 0; i < 10; i += 1) {
      // `a`: 3 opens a day, alternating, 2 or 3 notes; half both active on day 7.
      events.push(...pair(`a${i}`, { opensPerDay: 3, notesPerDay: 2 + (i % 2), bothDay7: i < 5 }));
      flags.push(flag(`a${i}`, "a"));
      // `b`: 1 open a day; everyone both active on day 7, and all added the widget.
      events.push(
        ...pair(`b${i}`, {
          opensPerDay: 1,
          notesPerDay: 2 + (i % 2),
          bothDay7: true,
          bothWidget: true,
        }),
      );
      flags.push(flag(`b${i}`, "b"));
    }
    const result = buildExperimentMetrics(events, flags, today, new Map([["home-layout", "a"]]));
    expect(result[0]?.baseline).toBe("a");

    const d7 = metric(result, "d7BothActive");
    expect(d7?.variants.map(({ estimate }) => estimate?.value)).toEqual([0.5, 1]);
    expect(d7?.variants[1]?.change).toBe("better");

    const opens = metric(result, "opensPerDay");
    // The day-7 open is outside days 0 to 6, so `b` stays at 1 a day.
    expect(opens?.variants.map(({ estimate }) => estimate?.value)).toEqual([3, 1]);
    expect(opens?.variants[1]?.vsBaseline?.value).toBe(-2);
    expect(opens?.variants[1]?.change).toBe("worse");

    const notes = metric(result, "notesPerDay");
    expect(notes?.variants[0]?.estimate?.value).toBeCloseTo(2.5);
    expect(notes?.variants[1]?.change).toBe("unclear");

    // Worse opens is a guardrail and warns; no secondary ever does.
    expect(result[0]?.warnings).toEqual([
      expect.objectContaining({ metric: "opensPerDay", variant: "b" }),
    ]);
    expect(result[0]?.warnings[0]?.text).toContain("App opens per pair per day is worse in b");
  });

  it("says too few under 5 pairs, and leaves out pairs younger than a week", () => {
    const events: Array<BuildEventRow> = [];
    const flags: Array<FlagRow> = [];
    for (let i = 0; i < 6; i += 1) {
      events.push(...pair(`a${i}`, { opensPerDay: 1 }));
      flags.push(flag(`a${i}`, "a"));
    }
    for (let i = 0; i < 4; i += 1) {
      events.push(...pair(`b${i}`, { opensPerDay: 1 }));
      flags.push(flag(`b${i}`, "b"));
    }
    // Three more `b` pairs, formed 6 days ago: not yet measured.
    for (let i = 4; i < 7; i += 1) {
      events.push(...pair(`b${i}`, { opensPerDay: 1, formedDay: addDays(today, -6) }));
      flags.push(flag(`b${i}`, "b"));
    }
    const result = buildExperimentMetrics(events, flags, today, new Map([["home-layout", "a"]]));
    const opens = metric(result, "opensPerDay");
    expect(opens?.variants.map(({ pairs }) => pairs)).toEqual([6, 4]);
    expect(opens?.variants[1]).toMatchObject({ estimate: null, vsBaseline: null, change: null });
    expect(opens?.variants[0]?.estimate?.value).toBe(1);
  });

  it("waits for crash data, and falls back to the first variant without a known default", () => {
    const events = [...pair("a0"), ...pair("b0")];
    const result = buildExperimentMetrics(events, [flag("a0", "x"), flag("b0", "w")], today);
    expect(result[0]?.baseline).toBe("w");
    expect(metric(result, "crashFree")).toMatchObject({
      status: "waiting",
      role: "guardrail",
      waitingFor: expect.stringContaining("#38"),
    });
  });
});
