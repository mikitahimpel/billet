import { describe, expect, it } from "vitest";
import {
  backoffMillis,
  deliveryHealth,
  enqueue,
  isDue,
  maxAttempts,
  nextAlarmAt,
  settle,
  type DeliveryEntry,
} from "../src/delivery-ledger.ts";

const fresh = enqueue(undefined, "note-1", "AlertPush", 1_000);

describe("enqueue", () => {
  it("starts a pending entry that is due now", () => {
    expect(fresh).toEqual({
      noteId: "note-1",
      lane: "AlertPush",
      status: "pending",
      attempts: 0,
      nextAttemptAt: 1_000,
    });
    expect(isDue(fresh, 1_000)).toBe(true);
  });

  it("returns the existing entry for a repeated send, whatever state it is in", () => {
    const delivered = settle(fresh, "Delivered", 2_000);
    expect(enqueue(delivered, "note-1", "AlertPush", 9_000)).toBe(delivered);
    expect(enqueue(fresh, "note-1", "AlertPush", 9_000)).toBe(fresh);
  });
});

describe("settle", () => {
  it("marks a delivery delivered, and ignores every later report", () => {
    const delivered = settle(fresh, "Delivered", 2_000);
    expect(delivered.status).toBe("delivered");
    expect(settle(delivered, "Retry", 3_000)).toBe(delivered);
    expect(settle(delivered, "Abandon", 3_000)).toBe(delivered);
    expect(isDue(delivered, 99_000)).toBe(false);
  });

  it("abandons on request, for example a dead token", () => {
    expect(settle(fresh, "Abandon", 2_000).status).toBe("abandoned");
  });

  it("retries with a growing wait, and is not due before it", () => {
    const first = settle(fresh, "Retry", 10_000);
    expect(first).toMatchObject({ status: "pending", attempts: 1, nextAttemptAt: 10_000 + 5_000 });
    expect(isDue(first, 14_999)).toBe(false);
    expect(isDue(first, 15_000)).toBe(true);
    const second = settle(first, "Retry", 15_000);
    expect(second).toMatchObject({ attempts: 2, nextAttemptAt: 15_000 + 10_000 });
  });

  it("gives up at the attempt limit", () => {
    let entry: DeliveryEntry = fresh;
    for (let i = 0; i < maxAttempts - 1; i++) entry = settle(entry, "Retry", 0);
    expect(entry.status).toBe("pending");
    entry = settle(entry, "Retry", 0);
    expect(entry).toMatchObject({ status: "abandoned", attempts: maxAttempts });
  });
});

describe("backoffMillis", () => {
  it("doubles and stops at 15 minutes", () => {
    expect([1, 2, 3, 4].map(backoffMillis)).toEqual([5_000, 10_000, 20_000, 40_000]);
    expect(backoffMillis(30)).toBe(15 * 60_000);
  });
});

describe("nextAlarmAt", () => {
  it("is the earliest pending time, and nothing once all are settled", () => {
    const later = { ...enqueue(undefined, "note-2", "WidgetPush", 5_000) };
    expect(nextAlarmAt([later, fresh])).toBe(1_000);
    expect(
      nextAlarmAt([settle(fresh, "Delivered", 0), settle(later, "Abandon", 0)]),
    ).toBeUndefined();
    expect(nextAlarmAt([])).toBeUndefined();
  });
});

describe("deliveryHealth", () => {
  it("counts each lane and rates only finished deliveries", () => {
    const one = (lane: string, outcome: "Delivered" | "Abandon" | "Retry", id: string) =>
      settle(enqueue(undefined, id, lane, 0), outcome, 0);
    expect(
      deliveryHealth([
        one("AlertPush", "Delivered", "a"),
        one("AlertPush", "Delivered", "b"),
        one("AlertPush", "Abandon", "c"),
        one("AlertPush", "Retry", "d"),
        one("WidgetPush", "Retry", "e"),
      ]),
    ).toEqual({
      AlertPush: { delivered: 2, abandoned: 1, pending: 1, successRate: 2 / 3 },
      WidgetPush: { delivered: 0, abandoned: 0, pending: 1, successRate: undefined },
    });
    expect(deliveryHealth([])).toEqual({});
  });
});
