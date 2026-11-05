import { Effect, Layer } from "effect";
import { NotesService } from "@billet/backend-notes/notes-service";
import type { NotesNotFound, NotesUnavailable } from "@billet/backend-notes/notes-error";
import { PairWallet } from "@billet/backend-payments/pair-wallet";
import { PaymentsNotFound, PaymentsUnavailable } from "@billet/backend-payments/payments-error";

const asPayments = (error: NotesNotFound | NotesUnavailable) =>
  error._tag === "NotesNotFound"
    ? new PaymentsNotFound()
    : new PaymentsUnavailable({ reason: error.reason, cause: error });

/** `PairWallet` on the pair's room, through `NotesService`, which opens a room not open yet. */
export const PairWalletLive: Layer.Layer<PairWallet, never, NotesService> = Layer.effect(
  PairWallet,
  Effect.gen(function* () {
    const notes = yield* NotesService;
    return PairWallet.of({
      balance: (pairId) => notes.walletBalance(pairId).pipe(Effect.mapError(asPayments)),
      enter: (pairId, credit) =>
        notes.creditPurchase(pairId, credit).pipe(Effect.mapError(asPayments)),
    });
  }),
);
