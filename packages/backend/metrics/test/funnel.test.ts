import { describe, expect, it } from "vitest";
import type { MetricEventName } from "@billet/contracts-domain/metrics";
import {
  addDays,
  buildReport,
  minimumPairsPerVariant,
  share,
  wilson,
  type EventRow,
} from "../src/funnel.ts";

const hour = 3_600_000;
const day0 = Date.UTC(2026, 10, 1, 12);

const row = (
  pairId: string,
  userId: string,
  name: MetricEventName,
  dayOffset: number,
  count = 1,
  hoursIntoDay = 0,
): EventRow => ({
  pairId,
  userId,
  name,
  day: addDays("2026-11-01", dayOffset),
  count,
  firstAt: day0 + dayOffset * 24 * hour + hoursIntoDay * hour,
});

/** A pair that formed on 2026-11-01, with both members. */
const formed = (pairId: string, a = `${pairId}-a`, b = `${pairId}-b`): Array<EventRow> => [
  row(pairId, a, "PairClaimed", 0),
  row(pairId, b, "PairClaimed", 0),
];

const today = "2026-11-20";

describe("addDays", () => {
  it("crosses months and leap days", () => {
    expect(addDays("2026-11-30", 1)).toBe("2026-12-01");
    expect(addDays("2028-02-28", 1)).toBe("2028-02-29");
    expect(addDays("2026-11-01", 30)).toBe("2026-12-01");
  });
});

describe("wilson", () => {
  it("has no interval for no pairs", () => {
    expect(wilson(0, 0)).toBeUndefined();
    expect(share(0, 0).share).toBeUndefined();
  });

  it("is wide for few pairs and narrow for many", () => {
    const small = wilson(3, 10);
    const large = wilson(300, 1_000);
    expect((small?.high ?? 0) - (small?.low ?? 0)).toBeGreaterThan(0.4);
    expect((large?.high ?? 0) - (large?.low ?? 0)).toBeLessThan(0.07);
  });

  it("stays between 0 and 1 even for none and for all", () => {
    expect(wilson(0, 5)?.low).toBe(0);
    expect(wilson(5, 5)?.high).toBe(1);
  });

  it("matches a known value: 20 of 100 is about 13% to 29%", () => {
    const interval = wilson(20, 100);
    expect(interval?.low).toBeCloseTo(0.1333, 3);
    expect(interval?.high).toBeCloseTo(0.2889, 3);
  });
});

describe("funnel", () => {
  it("is empty for no events", () => {
    const report = buildReport([], [], today);
    expect(report.pairsFormed).toBe(0);
    expect(report.invitesCreated).toBe(0);
    expect(report.medianToFirstNote).toBeUndefined();
    expect(report.days.every(({ eligible }) => eligible === 0)).toBe(true);
    expect(report.experiments).toEqual([]);
  });

  it("counts people who made an invite and how many of them ended up in a pair", () => {
    const report = buildReport(
      [
        row("", "ana", "InviteCreated", 0),
        row("", "ben", "InviteCreated", 0),
        row("", "ana", "InviteCreated", 1),
        ...formed("p1", "ana", "cal"),
      ],
      [],
      today,
    );
    expect(report.invitesCreated).toBe(2);
    expect(report.inviterPaired).toMatchObject({ count: 1, of: 2 });
    expect(report.pairsFormed).toBe(1);
  });

  it("counts a widget on both phones, and a note each way", () => {
    const report = buildReport(
      [
        ...formed("p1"),
        row("p1", "p1-a", "WidgetAdded", 0),
        row("p1", "p1-b", "WidgetAdded", 1),
        row("p1", "p1-a", "NoteSent", 0),
        row("p1", "p1-b", "NoteSent", 2),
        ...formed("p2"),
        row("p2", "p2-a", "WidgetAdded", 0),
        row("p2", "p2-a", "NoteSent", 0),
      ],
      [],
      today,
    );
    expect(report.widgetAddedByBoth).toMatchObject({ count: 1, of: 2 });
    expect(report.firstNoteBothWays).toMatchObject({ count: 1, of: 2 });
  });

  it("measures time to the first note, and until both had sent one", () => {
    const report = buildReport(
      [
        row("p1", "p1-a", "PairClaimed", 0, 1, 0),
        row("p1", "p1-b", "PairClaimed", 0, 1, 0),
        row("p1", "p1-a", "NoteSent", 0, 1, 2),
        row("p1", "p1-b", "NoteSent", 1, 1, 5),
      ],
      [],
      today,
    );
    expect(report.medianToFirstNote).toBe(2 * hour);
    expect(report.medianToFirstNoteBothWays).toBe(29 * hour);
  });

  it("takes the median over pairs, ignoring pairs that never sent", () => {
    const pairNoted = (id: string, hours: number) => [
      row(id, `${id}-a`, "PairClaimed", 0, 1, 0),
      row(id, `${id}-b`, "PairClaimed", 0, 1, 0),
      row(id, `${id}-a`, "NoteSent", 0, 1, hours),
    ];
    const report = buildReport(
      [...pairNoted("p1", 1), ...pairNoted("p2", 3), ...pairNoted("p3", 9), ...formed("p4")],
      [],
      today,
    );
    expect(report.medianToFirstNote).toBe(3 * hour);
  });

  describe("both active on day N", () => {
    const bothSend = (id: string, dayOffset: number) => [
      row(id, `${id}-a`, "NoteSent", dayOffset),
      row(id, `${id}-b`, "NoteSent", dayOffset),
    ];

    it("counts a pair where both partners sent a note exactly N days after it formed", () => {
      const report = buildReport(
        [...formed("p1"), ...bothSend("p1", 7), ...formed("p2"), ...bothSend("p2", 6)],
        [],
        today,
      );
      const day7 = report.days.find(({ day }) => day === 7);
      expect(day7?.bothSentNote).toMatchObject({ count: 1, of: 2 });
    });

    it("does not count one partner alone", () => {
      const report = buildReport([...formed("p1"), row("p1", "p1-a", "NoteSent", 7)], [], today);
      expect(report.days.find(({ day }) => day === 7)?.bothSentNote.count).toBe(0);
    });

    it("counts opening the app as active in the looser measure only", () => {
      const report = buildReport(
        [...formed("p1"), row("p1", "p1-a", "NoteSent", 7), row("p1", "p1-b", "AppOpened", 7)],
        [],
        today,
      );
      const day7 = report.days.find(({ day }) => day === 7);
      expect(day7?.bothSentNote.count).toBe(0);
      expect(day7?.bothActive.count).toBe(1);
    });

    it("only counts pairs old enough to have a day N, so a young pair is not a failure", () => {
      const young = [row("p9", "p9-a", "PairClaimed", 17), row("p9", "p9-b", "PairClaimed", 17)];
      const reportYoung = buildReport([...formed("p1"), ...young], [], "2026-11-20");
      const day7 = reportYoung.days.find(({ day }) => day === 7);
      expect(day7?.eligible).toBe(1);
      const day30 = reportYoung.days.find(({ day }) => day === 30);
      expect(day30?.eligible).toBe(0);
    });

    it("counts a pair on day N once its day has begun", () => {
      const report = buildReport([...formed("p1")], [], "2026-11-08");
      expect(report.days.find(({ day }) => day === 7)?.eligible).toBe(1);
      expect(
        buildReport([...formed("p1")], [], "2026-11-07").days.find(({ day }) => day === 7)
          ?.eligible,
      ).toBe(0);
    });
  });

  it("averages notes per pair per day over the first week of pairs a week old", () => {
    const report = buildReport(
      [
        ...formed("p1"),
        row("p1", "p1-a", "NoteSent", 0, 7),
        row("p1", "p1-b", "NoteSent", 3, 7),
        row("p1", "p1-a", "NoteSent", 9, 100),
        ...formed("p2"),
        row("p2", "p2-a", "NoteSent", 1, 0),
      ],
      [],
      today,
    );
    expect(report.notesPerPairPerDay).toEqual({ pairs: 2, mean: 1 });
  });

  it("totals notes by day, and counts watched against skipped openings", () => {
    const report = buildReport(
      [
        ...formed("p1"),
        row("p1", "p1-a", "NoteSent", 0, 2),
        row("p1", "p1-b", "NoteSent", 0, 3),
        row("p1", "p1-a", "OpeningWatched", 0, 1),
        row("p1", "p1-b", "OpeningSkipped", 0, 4),
      ],
      [],
      today,
    );
    expect(report.daily).toEqual([{ day: "2026-11-01", notes: 5, pairsWithNote: 1 }]);
    expect(report.opening).toEqual({ watched: 1, skipped: 4 });
  });

  it("ignores a pair that has no claim row, since its start is unknown", () => {
    const report = buildReport([row("orphan", "o-a", "NoteSent", 3)], [], today);
    expect(report.pairsFormed).toBe(0);
  });

  describe("experiments", () => {
    const pairs = (prefix: string, count: number, bothSend: number): Array<EventRow> =>
      Array.from({ length: count }, (_, i) => {
        const id = `${prefix}${i}`;
        return [
          ...formed(id),
          ...(i < bothSend
            ? [row(id, `${id}-a`, "NoteSent", 7), row(id, `${id}-b`, "NoteSent", 7)]
            : []),
        ];
      }).flat();

    const flags = (prefix: string, count: number, variant: string) =>
      Array.from({ length: count }, (_, i) => ({
        pairId: `${prefix}${i}`,
        experimentKey: "home-direction",
        variant,
      }));

    it("compares variants by the share of pairs where both sent a note on day 7", () => {
      const report = buildReport(
        [...pairs("a", 10, 6), ...pairs("b", 10, 3)],
        [...flags("a", 10, "window-seat"), ...flags("b", 10, "sunset-lamp")],
        today,
      );
      const [experiment] = report.experiments;
      expect(experiment?.key).toBe("home-direction");
      expect(experiment?.variants.map((v) => [v.variant, v.pairs, v.northStar.count])).toEqual([
        ["sunset-lamp", 10, 3],
        ["window-seat", 10, 6],
      ]);
    });

    it("says plainly that a small test cannot pick a winner", () => {
      const report = buildReport(
        [...pairs("a", 10, 6), ...pairs("b", 10, 3)],
        [...flags("a", 10, "x"), ...flags("b", 10, "y")],
        today,
      );
      expect(report.experiments[0]?.caution).toMatch(/not.*pick a winner/);
    });

    it("stops warning about size once every variant has enough pairs", () => {
      const n = minimumPairsPerVariant;
      const report = buildReport(
        [...pairs("a", n, 50), ...pairs("b", n, 20)],
        [...flags("a", n, "x"), ...flags("b", n, "y")],
        today,
      );
      expect(report.experiments[0]?.caution).not.toMatch(/winner/);
    });

    it("leaves out assignments for pairs with no events", () => {
      const report = buildReport([], flags("ghost", 3, "x"), today);
      expect(report.experiments).toEqual([]);
    });
  });
});
