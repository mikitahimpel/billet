import { Effect } from "effect";
import { freeInk } from "@billet/contracts-domain/inks";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { ParcelOffer } from "@billet/contracts-domain/plus";
import { starterItems } from "@billet/contracts-domain/shop";
import type { ShopResponse } from "@billet/contracts-http-api/shop";
import { PaymentsUnavailable } from "../src/payments-error.ts";
import type { PairWallet } from "../src/pair-wallet.ts";

export interface InMemoryPairWallet {
  readonly wallet: PairWallet["Service"];
  /** The pair's entries, oldest first, as `[id, amount]`. */
  readonly entries: (pairId: string) => ReadonlyArray<readonly [string, number]>;
  readonly balance: (pairId: string) => number;
  /** Coins earned (positive) or spent (negative) in the app, as `app:<entries before it>`. */
  readonly adjust: (pairId: string, amount: number) => void;
  /** The next `n` calls to `enter` or `grant` fail, as a room that can't be reached. */
  readonly failNext: (n: number) => void;
  /** Pieces the pair owns besides the free ones, as `<tag>:<id>`. */
  readonly owned: (pairId: string) => ReadonlyArray<string>;
}

const keyOf = (piece: ParcelOffer) => {
  switch (piece._tag) {
    case "Ink":
      return `Ink:${piece.ink}`;
    case "Item":
      return `Item:${piece.item}`;
    case "Postage":
      return `Postage:${piece.postage}`;
  }
};

/** The room's wallet rules for bought coins: once per id, a refund the whole pack, so the balance can go negative. */
export const makeInMemoryPairWallet = (): InMemoryPairWallet => {
  const pairs = new Map<string, Map<string, number>>();
  const pieces = new Map<string, Map<string, ParcelOffer>>();
  let failures = 0;
  const piecesOf = (pairId: string) => {
    const existing = pieces.get(pairId);
    if (existing !== undefined) return existing;
    const created = new Map<string, ParcelOffer>();
    pieces.set(pairId, created);
    return created;
  };
  const shopOf = (pairId: string): ShopResponse => {
    const owned = [...piecesOf(pairId).values()];
    return {
      balance: sum(pairId),
      inks: [freeInk, ...owned.flatMap((piece) => (piece._tag === "Ink" ? [piece.ink] : []))],
      items: [
        ...starterItems,
        ...owned.flatMap((piece) => (piece._tag === "Item" ? [piece.item] : [])),
      ],
      postage: owned.flatMap((piece) => (piece._tag === "Postage" ? [piece.postage] : [])),
      wishlist: [],
      bonuses: [],
    };
  };
  const of = (pairId: string) => {
    const existing = pairs.get(pairId);
    if (existing !== undefined) return existing;
    const created = new Map<string, number>();
    pairs.set(pairId, created);
    return created;
  };
  const sum = (pairId: string) => [...of(pairId).values()].reduce((a, b) => a + b, 0);
  const wallet: PairWallet["Service"] = {
    balance: (pairId: PairId) => Effect.sync(() => sum(pairId)),
    enter: (pairId, credit) =>
      Effect.suspend(() => {
        if (failures > 0) {
          failures -= 1;
          return Effect.fail(new PaymentsUnavailable({ reason: "room-unavailable" }));
        }
        const entries = of(pairId);
        const earlier = entries.get(credit.id);
        if (earlier !== undefined) {
          return Effect.succeed({ balance: sum(pairId), coins: Math.abs(earlier) });
        }
        const coins =
          "coins" in credit ? credit.coins : Math.abs(entries.get(credit.reverses) ?? 0);
        const amount = credit.kind === "purchase" ? coins : -coins;
        entries.set(credit.id, amount);
        return Effect.succeed({ balance: sum(pairId), coins: Math.abs(amount) });
      }),
    shop: (pairId) => Effect.sync(() => shopOf(pairId)),
    grant: (pairId, piece) =>
      Effect.suspend(() => {
        if (failures > 0) {
          failures -= 1;
          return Effect.fail(new PaymentsUnavailable({ reason: "room-unavailable" }));
        }
        piecesOf(pairId).set(keyOf(piece), piece);
        return Effect.succeed(shopOf(pairId));
      }),
  };
  return {
    wallet,
    entries: (pairId) => [...of(pairId).entries()],
    balance: sum,
    adjust: (pairId, amount) => void of(pairId).set(`app:${of(pairId).size}`, amount),
    failNext: (n) => {
      failures = n;
    },
    owned: (pairId) => [...piecesOf(pairId).keys()],
  };
};
