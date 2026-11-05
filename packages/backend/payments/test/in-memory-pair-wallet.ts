import { Effect } from "effect";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { PaymentsUnavailable } from "../src/payments-error.ts";
import type { PairWallet } from "../src/pair-wallet.ts";

export interface InMemoryPairWallet {
  readonly wallet: PairWallet["Service"];
  /** The pair's entries, oldest first, as `[id, amount]`. */
  readonly entries: (pairId: string) => ReadonlyArray<readonly [string, number]>;
  readonly balance: (pairId: string) => number;
  /** Coins earned (positive) or spent (negative) in the app, as `app:<entries before it>`. */
  readonly adjust: (pairId: string, amount: number) => void;
  /** The next `n` calls to `enter` fail, as a room that can't be reached. */
  readonly failNext: (n: number) => void;
}

/** The room's wallet rules for bought coins: once per id, a refund at most the balance. */
export const makeInMemoryPairWallet = (): InMemoryPairWallet => {
  const pairs = new Map<string, Map<string, number>>();
  let failures = 0;
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
        const amount = credit.kind === "buy" ? coins : -Math.min(coins, sum(pairId));
        entries.set(credit.id, amount);
        return Effect.succeed({ balance: sum(pairId), coins: Math.abs(amount) });
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
  };
};
