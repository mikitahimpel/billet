import { Schema } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import { ParcelId, plusProductOf } from "@billet/contracts-domain/plus";
import type { Parcel, PlusState } from "@billet/contracts-http-api/plus";
import type { StoredPeriod, StoredSubscription } from "./plus-repository.ts";

const decodeParcelId = Schema.decodeSync(ParcelId);

const iso = (millis: number) => new Date(millis).toISOString();

/** The same day `months` later, in UTC; a day the month lacks becomes its last day. */
export const addMonths = (at: number, months: number): number => {
  const date = new Date(at);
  const target = new Date(at);
  target.setUTCDate(1);
  target.setUTCMonth(date.getUTCMonth() + months);
  const lastDay = new Date(
    Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0),
  ).getUTCDate();
  target.setUTCDate(Math.min(date.getUTCDate(), lastDay));
  return target.getTime();
};

export interface DerivedParcel {
  readonly id: ParcelId;
  readonly arrived: number;
  readonly payer: UserId;
  readonly transactionId: string;
}

/**
 * The parcels a paid period has brought by `now`: one for a month, one a month for a year,
 * whether or not anyone opened the app. A refunded period brings none. Ids depend only on the
 * transaction, so asking twice never makes two.
 */
export const parcelsOfPeriod = (
  period: StoredPeriod,
  now: number,
): ReadonlyArray<DerivedParcel> => {
  const product = plusProductOf(period.productId);
  if (product === undefined || period.revokedAt !== null) return [];
  return Array.from({ length: product.parcels }, (_, month) => month).flatMap((month) => {
    const arrived = addMonths(period.purchasedAt, month);
    if (arrived > now) return [];
    const id =
      product.parcels === 1
        ? `parcel:${period.transactionId}`
        : `parcel:${period.transactionId}:${month + 1}`;
    return [
      {
        id: decodeParcelId(id),
        arrived,
        payer: period.userId,
        transactionId: period.transactionId,
      },
    ];
  });
};

/** When the next parcel of a live subscription comes, if one is due. */
const nextParcelOf = (
  subscription: StoredSubscription,
  periods: ReadonlyArray<StoredPeriod>,
  now: number,
): number | undefined => {
  const product = plusProductOf(subscription.productId);
  if (product === undefined) return undefined;
  if (product.parcels === 1) {
    return subscription.autoRenew && subscription.expiresAt > now
      ? subscription.expiresAt
      : undefined;
  }
  const current = periods
    .filter(
      (period) =>
        period.originalTransactionId === subscription.originalTransactionId &&
        period.revokedAt === null &&
        period.purchasedAt <= now &&
        period.expiresAt > now,
    )
    .toSorted((a, b) => b.purchasedAt - a.purchasedAt)[0];
  if (current === undefined) return undefined;
  for (let month = 1; month < product.parcels; month += 1) {
    const at = addMonths(current.purchasedAt, month);
    if (at > now) return at;
  }
  return subscription.autoRenew ? current.expiresAt : undefined;
};

type Live =
  | { readonly _tag: "Active"; readonly until: number }
  | { readonly _tag: "Ending"; readonly until: number }
  | { readonly _tag: "Grace" }
  | { readonly _tag: "Over" };

/** One subscription at `now`. Apple keeps the old `expiresAt` through a billing grace period. */
export const liveness = (subscription: StoredSubscription, now: number): Live => {
  if (subscription.revokedAt !== null) return { _tag: "Over" };
  if (subscription.expiresAt > now) {
    return subscription.autoRenew
      ? { _tag: "Active", until: subscription.expiresAt }
      : { _tag: "Ending", until: subscription.expiresAt };
  }
  if (subscription.graceUntil !== null && subscription.graceUntil > now) return { _tag: "Grace" };
  return { _tag: "Over" };
};

const rank = (live: Live): number => {
  switch (live._tag) {
    case "Active":
      return 3;
    case "Ending":
      return 2;
    case "Grace":
      return 1;
    case "Over":
      return 0;
  }
};

/** The member's best subscription and how it stands, when they have one that is not over. */
const bestOf = (subscriptions: ReadonlyArray<StoredSubscription>, now: number) =>
  subscriptions
    .map((subscription) => ({ subscription, live: liveness(subscription, now) }))
    .filter(({ live }) => live._tag !== "Over")
    .toSorted((a, b) => rank(b.live) - rank(a.live))[0];

export interface PairPlus {
  readonly state: PlusState;
  readonly parcels: ReadonlyArray<Parcel>;
  readonly opened: number;
  readonly nextParcel?: string;
  readonly bothPay: boolean;
}

export interface PlusFacts {
  readonly caller: UserId;
  /** The caller and, when paired, the partner. */
  readonly members: ReadonlyArray<UserId>;
  readonly subscriptions: ReadonlyArray<StoredSubscription>;
  readonly periods: ReadonlyArray<StoredPeriod>;
  /** The ids of parcels already opened, by any pair. */
  readonly opened: ReadonlySet<string>;
}

/** Parcels of the members' Plus that wait to be opened, oldest first. */
export const waitingParcels = (facts: PlusFacts, now: number): ReadonlyArray<DerivedParcel> =>
  facts.periods
    .filter((period) => facts.members.includes(period.userId))
    .flatMap((period) => parcelsOfPeriod(period, now))
    .filter((parcel) => !facts.opened.has(parcel.id))
    .toSorted((a, b) => a.arrived - b.arrived || a.id.localeCompare(b.id));

/**
 * The pair's Plus as `caller` sees it. The caller's own subscription wins; the partner's shows as
 * `Shared`, with no plan or dates. A pair has Plus while either member has one not over.
 */
export const pairPlus = (facts: PlusFacts, now: number): PairPlus => {
  const of = (user: UserId) => facts.subscriptions.filter(({ userId }) => userId === user);
  const partner = facts.members.find((member) => member !== facts.caller);
  const mine = bestOf(of(facts.caller), now);
  const theirs = partner === undefined ? undefined : bestOf(of(partner), now);
  const memberSubscriptions = facts.subscriptions.filter(({ userId }) =>
    facts.members.includes(userId),
  );
  const parcels = waitingParcels(facts, now).map(({ id, arrived }) => ({
    id,
    arrived: iso(arrived),
  }));
  const opened = facts.periods
    .filter((period) => facts.members.includes(period.userId))
    .flatMap((period) => parcelsOfPeriod(period, now))
    .filter((parcel) => facts.opened.has(parcel.id)).length;
  const base = { parcels, opened, bothPay: mine !== undefined && theirs !== undefined };

  if (mine !== undefined) {
    const product = plusProductOf(mine.subscription.productId);
    const plan = product?.plan ?? "monthly";
    const next = nextParcelOf(mine.subscription, facts.periods, now);
    const nextParcel = next === undefined ? {} : { nextParcel: iso(next) };
    switch (mine.live._tag) {
      case "Active":
        return {
          ...base,
          ...nextParcel,
          state: { _tag: "Active", plan, renewsOn: iso(mine.live.until) },
        };
      case "Ending":
        return {
          ...base,
          ...nextParcel,
          state: { _tag: "Ending", plan, until: iso(mine.live.until) },
        };
      case "Grace":
      case "Over":
        return { ...base, ...nextParcel, state: { _tag: "Grace", plan } };
    }
  }
  if (theirs !== undefined) return { ...base, state: { _tag: "Shared" } };
  return { ...base, state: memberSubscriptions.length > 0 ? { _tag: "Ended" } : { _tag: "None" } };
};
