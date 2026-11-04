import { describe, expect, it } from "vitest";
import {
  compareValues,
  deltaOf,
  diffConfig,
  experimentActions,
  funnelSteps,
  matchesQuery,
  mergeAudit,
  relativeTime,
  sortRows,
  sparkPath,
  splitShares,
  statePill,
} from "../web/lib.js";

const now = Date.parse("2026-11-04T12:00:00Z");
const MIN = 60_000;
const DAY = 24 * 60 * MIN;

describe("relative times", () => {
  it("reads like GitHub's", () => {
    expect(relativeTime(now - 20_000, now)).toBe("just now");
    expect(relativeTime(now - MIN, now)).toBe("1 minute ago");
    expect(relativeTime(now - 5 * MIN, now)).toBe("5 minutes ago");
    expect(relativeTime(now - 3 * 60 * MIN, now)).toBe("3 hours ago");
    expect(relativeTime(now - DAY, now)).toBe("yesterday");
    expect(relativeTime(now - 4 * DAY, now)).toBe("4 days ago");
    expect(relativeTime(now - 40 * DAY, now)).toBe("on Sep 25");
    expect(relativeTime(Date.parse("2025-03-02T00:00:00Z"), now)).toBe("on Mar 2, 2025");
  });

  it("handles the future and the missing", () => {
    expect(relativeTime(now + 10 * MIN, now)).toBe("in 10 minutes");
    expect(relativeTime(now + DAY, now)).toBe("tomorrow");
    expect(relativeTime(null, now)).toBe("never");
  });
});

describe("sorting and searching", () => {
  const rows = [
    { key: "b", n: 2, at: null },
    { key: "a10", n: 10, at: 3 },
    { key: "a9", n: 9, at: 1 },
  ];

  it("sorts numbers by size and text naturally, with empty values last both ways", () => {
    expect(sortRows(rows, (r) => r.key, "asc").map((r) => r.key)).toEqual(["a9", "a10", "b"]);
    expect(sortRows(rows, (r) => r.n, "desc").map((r) => r.n)).toEqual([10, 9, 2]);
    expect(sortRows(rows, (r) => r.at, "asc").map((r) => r.key)).toEqual(["a9", "a10", "b"]);
    expect(sortRows(rows, (r) => r.at, "desc").map((r) => r.key)).toEqual(["a10", "a9", "b"]);
    expect(compareValues("", "x")).toBeGreaterThan(0);
  });

  it("matches every word of the query, in any case", () => {
    expect(matchesQuery("home-direction running", "")).toBe(true);
    expect(matchesQuery("home-direction running", "RUN home")).toBe(true);
    expect(matchesQuery("home-direction running", "home stopped")).toBe(false);
  });
});

describe("changes against the previous period", () => {
  it("shows counts in percent and shares in points", () => {
    expect(deltaOf(12, 10)).toEqual({ kind: "up", text: "+20%" });
    expect(deltaOf(9.5, 10)).toEqual({ kind: "down", text: "−5%" });
    expect(deltaOf(0.42, 0.4, "pp")).toEqual({ kind: "up", text: "+2 pts" });
    expect(deltaOf(0.4, 0.4, "pp")).toEqual({ kind: "flat", text: "no change" });
  });

  it("does not invent a percentage from nothing", () => {
    expect(deltaOf(5, 0)).toEqual({ kind: "none", text: "new this period" });
    expect(deltaOf(0, 0)).toEqual({ kind: "flat", text: "no change" });
    expect(deltaOf(null, 3).kind).toBe("none");
  });
});

describe("the funnel", () => {
  it("converts each step from the last counted one, skipping installs", () => {
    const steps = funnelSteps([
      { step: "install", label: "Installed", count: null },
      { step: "signedIn", label: "Signed in", count: 200 },
      { step: "paired", label: "Paired", count: 120 },
      { step: "firstNote", label: "First note", count: 90 },
    ]);
    expect(steps.map(({ fromPrevious }) => fromPrevious)).toEqual([null, null, 0.6, 0.75]);
    expect(steps.map(({ fromFirst }) => fromFirst)).toEqual([null, null, 0.6, 0.45]);
  });
});

describe("the sparkline", () => {
  it("draws a line through the points and breaks it at a gap", () => {
    expect(sparkPath([0, 10], 100, 20, 0)).toBe("M0.0,20.0L100.0,0.0");
    expect(sparkPath([1, null, 1], 10, 10, 0)).toBe("M0.0,0.0M10.0,0.0");
    expect(sparkPath([null, null], 10, 10)).toBe("");
  });
});

describe("configs", () => {
  it("lists only the fields that changed", () => {
    const before = { exposure: 50, weights: { a: 1, b: 1 }, targeting: {} };
    const after = { exposure: 100, weights: { a: 1, b: 0 }, targeting: { pairIds: ["p1"] } };
    expect(diffConfig(before, after)).toEqual([
      { path: "exposure", before: 50, after: 100 },
      { path: "weights.b", before: 1, after: 0 },
      { path: "targeting.pairIds", before: undefined, after: ["p1"] },
    ]);
    expect(diffConfig(before, before)).toEqual([]);
  });

  it("turns weights into shares", () => {
    expect(splitShares({ a: 1, b: 3 })).toEqual({ a: 0.25, b: 0.75 });
    expect(splitShares({ a: 0, b: 0 })).toEqual({ a: 0, b: 0 });
  });

  it("offers the actions an experiment's state allows", () => {
    expect(experimentActions({ status: "draft", killed: false })).toEqual(["start", "kill"]);
    expect(experimentActions({ status: "running", killed: false })).toEqual(["stop", "kill"]);
    expect(experimentActions({ status: "stopped", killed: true })).toEqual(["start", "unkill"]);
  });

  it("shows killed over any status", () => {
    expect(statePill({ status: "running", killed: true })).toEqual({ tone: "bad", text: "killed" });
    expect(statePill({ status: "running", killed: false }).tone).toBe("good");
    expect(statePill({ status: "draft", killed: false }).text).toBe("draft");
  });
});

describe("the audit log", () => {
  it("merges flag and status changes, newest first, each status with the one before it", () => {
    const rows = mergeAudit(
      [
        { at: 30, by: "o", key: "home", action: "start" },
        { at: 10, by: "o", key: "home", action: "override", pairId: "p1" },
      ],
      [
        { at: 20, by: "o", version: 2, status: { v: 2 } },
        { at: 5, by: "o", version: 1, status: { v: 1 } },
      ],
    );
    expect(rows.map(({ at, area }) => [at, area])).toEqual([
      [30, "flag"],
      [20, "maintenance"],
      [10, "pair"],
      [5, "maintenance"],
    ]);
    expect(rows[1]).toMatchObject({ subject: "status v2", previous: { v: 1 } });
    expect(rows[3]?.previous).toBeNull();
  });
});
