import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import type { StoredPeriod, StoredSubscription } from "../src/plus-repository.ts";
import { addMonths, pairPlus, parcelsOfPeriod, type PlusFacts } from "../src/plus-rules.ts";

const user = Schema.decodeSync(UserId);
const [leo, mia] = [user("leo"), user("mia")];
const day = 86_400_000;
const start = Date.UTC(2026, 0, 31, 12);

const subscription = (
  userId: UserId,
  change: Partial<StoredSubscription> = {},
): StoredSubscription => ({
  originalTransactionId: `otid-${userId}`,
  userId,
  productId: "com.ourio.app.plus.monthly",
  environment: "Sandbox",
  expiresAt: addMonths(start, 1),
  autoRenew: true,
  graceUntil: null,
  revokedAt: null,
  createdAt: start,
  updatedAt: start,
  ...change,
});

const period = (userId: UserId, change: Partial<StoredPeriod> = {}): StoredPeriod => ({
  transactionId: `tx-${userId}`,
  originalTransactionId: `otid-${userId}`,
  userId,
  productId: "com.ourio.app.plus.monthly",
  purchasedAt: start,
  expiresAt: addMonths(start, 1),
  revokedAt: null,
  ...change,
});

const facts = (change: Partial<PlusFacts> = {}): PlusFacts => ({
  caller: leo,
  members: [leo, mia],
  subscriptions: [],
  periods: [],
  opened: new Set(),
  ...change,
});

describe("addMonths", () => {
  it("keeps the day, or takes the month's last when it has none", () => {
    expect(new Date(addMonths(start, 1)).toISOString()).toBe("2026-02-28T12:00:00.000Z");
    expect(new Date(addMonths(start, 2)).toISOString()).toBe("2026-03-31T12:00:00.000Z");
    expect(new Date(addMonths(start, 12)).toISOString()).toBe("2027-01-31T12:00:00.000Z");
    expect(addMonths(start, 0)).toBe(start);
  });
});

describe("parcels of a paid period", () => {
  it("brings one parcel for a month, at once", () => {
    expect(parcelsOfPeriod(period(leo), start).map(({ id }) => id)).toEqual(["parcel:tx-leo"]);
    expect(parcelsOfPeriod(period(leo), start - 1)).toEqual([]);
  });

  it("brings one a month for a year, twelve and no more", () => {
    const year = period(leo, {
      productId: "com.ourio.app.plus.yearly",
      expiresAt: addMonths(start, 12),
    });
    expect(parcelsOfPeriod(year, start + day).map(({ id }) => id)).toEqual(["parcel:tx-leo:1"]);
    expect(parcelsOfPeriod(year, addMonths(start, 2))).toHaveLength(3);
    const all = parcelsOfPeriod(year, addMonths(start, 40));
    expect(all).toHaveLength(12);
    expect(all.at(-1)?.id).toBe("parcel:tx-leo:12");
  });

  it("brings nothing for a refunded period or a product that is not Plus", () => {
    expect(parcelsOfPeriod(period(leo, { revokedAt: start }), start + day)).toEqual([]);
    expect(
      parcelsOfPeriod(period(leo, { productId: "com.ourio.app.coins.100" }), start + day),
    ).toEqual([]);
  });
});

describe("the pair's Plus", () => {
  const now = start + day;

  it("is None for a pair that never had it", () => {
    expect(pairPlus(facts(), now)).toEqual({
      state: { _tag: "None" },
      parcels: [],
      opened: 0,
      bothPay: false,
    });
  });

  it("is the payer's own plan and the partner's Shared, with the same parcels", () => {
    const records = { subscriptions: [subscription(leo)], periods: [period(leo)] };
    const payer = pairPlus(facts(records), now);
    expect(payer.state).toEqual({
      _tag: "Active",
      plan: "monthly",
      renewsOn: new Date(addMonths(start, 1)).toISOString(),
    });
    expect(payer.nextParcel).toBe(new Date(addMonths(start, 1)).toISOString());
    const partner = pairPlus(facts({ ...records, caller: mia }), now);
    expect(partner.state).toEqual({ _tag: "Shared" });
    expect(partner.nextParcel).toBeUndefined();
    expect(partner.parcels).toEqual(payer.parcels);
    expect(payer.parcels.map(({ id }) => id)).toEqual(["parcel:tx-leo"]);
  });

  it("tells the partner nothing when the payer cancels or fails to pay", () => {
    for (const change of [
      { autoRenew: false },
      { expiresAt: start, graceUntil: start + 16 * day },
    ]) {
      const records = { subscriptions: [subscription(leo, change)], periods: [period(leo)] };
      expect(pairPlus(facts({ ...records, caller: mia }), now).state).toEqual({ _tag: "Shared" });
    }
  });

  it("is Ending after a cancel, Grace while Apple retries, Ended after", () => {
    const of = (change: Partial<StoredSubscription>) =>
      pairPlus(facts({ subscriptions: [subscription(leo, change)], periods: [period(leo)] }), now)
        .state;
    expect(of({ autoRenew: false })).toEqual({
      _tag: "Ending",
      plan: "monthly",
      until: new Date(addMonths(start, 1)).toISOString(),
    });
    expect(of({ expiresAt: start, graceUntil: now + day })).toEqual({
      _tag: "Grace",
      plan: "monthly",
    });
    expect(of({ expiresAt: start, graceUntil: start })).toEqual({ _tag: "Ended" });
    expect(of({ revokedAt: start })).toEqual({ _tag: "Ended" });
  });

  it("keeps every parcel not opened after Plus ends, and counts the opened", () => {
    const plus = pairPlus(
      facts({
        subscriptions: [subscription(leo, { expiresAt: start })],
        periods: [period(leo), period(leo, { transactionId: "tx-2", purchasedAt: start + 1 })],
        opened: new Set(["parcel:tx-leo"]),
      }),
      now + 90 * day,
    );
    expect(plus.state).toEqual({ _tag: "Ended" });
    expect(plus.parcels.map(({ id }) => id)).toEqual(["parcel:tx-2"]);
    expect(plus.opened).toBe(1);
  });

  it("says when both pay, and shows the caller's own plan", () => {
    const plus = pairPlus(
      facts({
        subscriptions: [subscription(leo), subscription(mia, { autoRenew: false })],
        periods: [period(leo), period(mia)],
        caller: mia,
      }),
      now,
    );
    expect(plus.bothPay).toBe(true);
    expect(plus.state._tag).toBe("Ending");
    expect(plus.parcels).toHaveLength(2);
  });

  it("leaves out a former partner's subscription and parcels", () => {
    const plus = pairPlus(
      facts({
        members: [leo],
        subscriptions: [subscription(mia)],
        periods: [period(mia)],
      }),
      now,
    );
    expect(plus.state).toEqual({ _tag: "None" });
    expect(plus.parcels).toEqual([]);
  });

  it("names the next month of a year", () => {
    const year = {
      productId: "com.ourio.app.plus.yearly",
      expiresAt: addMonths(start, 12),
    };
    const plus = pairPlus(
      facts({ subscriptions: [subscription(leo, year)], periods: [period(leo, year)] }),
      addMonths(start, 3) + day,
    );
    expect(plus.nextParcel).toBe(new Date(addMonths(start, 4)).toISOString());
    expect(plus.parcels).toHaveLength(4);
  });
});
