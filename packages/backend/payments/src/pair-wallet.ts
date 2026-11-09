import { Context, type Effect } from "effect";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { PurchaseCredit } from "@billet/backend-pair-room/room-service";
import type { PaymentsNotFound, PaymentsUnavailable } from "./payments-error.ts";

/** The balance of the pair's wallet after a change, and the coins that change moved. */
export interface WalletChange {
  readonly balance: number;
  /** Positive: what a credit paid in or a refund took back. A repeated change answers its first. */
  readonly coins: number;
}

/** The wallet the app shows and spends from, in the pair's room; bought coins enter here and in
 * the payments ledger. A pair whose room can't be opened (it ended) is `PaymentsNotFound`. */
export class PairWallet extends Context.Service<
  PairWallet,
  {
    readonly balance: (
      pairId: PairId,
    ) => Effect.Effect<number, PaymentsNotFound | PaymentsUnavailable>;
    /** Enters the change once per entry id; a repeat changes nothing. */
    readonly enter: (
      pairId: PairId,
      credit: PurchaseCredit,
    ) => Effect.Effect<WalletChange, PaymentsNotFound | PaymentsUnavailable>;
  }
>()("@billet/backend-payments/PairWallet") {}
