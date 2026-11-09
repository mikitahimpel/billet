import { Clock, Context, Effect, Layer, Option, Redacted, Schema } from "effect";
import type { Signature } from "effect/crypto";
import { CoinEntryId } from "@billet/contracts-domain/coins";
import type { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { acceptedBundleIds, coinPackOf } from "@billet/contracts-domain/coin-packs";
import type {
  MockPurchaseRequest,
  PurchaseResponse,
  PurchasesResponse,
} from "@billet/contracts-http-api/purchase";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { verifySignedData } from "./app-store-signed-data.ts";
import { InvalidPurchase, PaymentsNotFound, PaymentsUnavailable } from "./payments-error.ts";
import { PaymentsConfig } from "./payments-config.ts";
import { PairWallet } from "./pair-wallet.ts";
import {
  CoinOwner,
  entryIds,
  type NewPurchase,
  PaymentsRepository,
  type StoredNotification,
  type StoredPurchase,
} from "./payments-repository.ts";

/** The fields of a StoreKit 2 transaction (`JWSTransactionDecodedPayload`) that matter here. */
const Transaction = Schema.Struct({
  transactionId: Schema.String.check(Schema.isNonEmpty()),
  originalTransactionId: Schema.String.check(Schema.isNonEmpty()),
  bundleId: Schema.String,
  productId: Schema.String,
  type: Schema.String,
  environment: Schema.String,
  purchaseDate: Schema.Number,
  revocationDate: Schema.optional(Schema.Number),
});
type Transaction = typeof Transaction.Type;

/** An App Store Server Notification V2 (`responseBodyV2DecodedPayload`), as far as it is read. */
const Notification = Schema.Struct({
  notificationType: Schema.String,
  subtype: Schema.optional(Schema.String),
  notificationUUID: Schema.String.check(Schema.isNonEmpty()),
  data: Schema.optional(
    Schema.Struct({
      bundleId: Schema.optional(Schema.String),
      environment: Schema.optional(Schema.String),
      signedTransactionInfo: Schema.optional(Schema.String),
    }),
  ),
});

const shapeOf =
  <S extends Schema.Top & { readonly DecodingServices: never }>(schema: S, reason: string) =>
  (input: unknown) =>
    Schema.decodeUnknownEffect(schema)(input).pipe(
      Effect.mapError(() => new InvalidPurchase({ reason })),
    );

const decodeOwner = Schema.decodeSync(CoinOwner);
const decodePairId = Schema.decodeSync(PairId);
const decodeEntryId = Schema.decodeSync(CoinEntryId);

const demoPrefix = "demo:";

/** The ledger of a demo room on the dev stage, which has no pair. */
export const demoOwner = (code: string): CoinOwner => decodeOwner(`${demoPrefix}${code}`);

/** The pair whose wallet an owner's coins go to. A demo room has none and keeps only the ledger. */
const pairOf = (owner: CoinOwner): PairId | undefined =>
  owner.startsWith(demoPrefix) ? undefined : decodePairId(owner);

const iso = (millis: number) => new Date(millis).toISOString();

/** Purchases and coins go through here; routes never see the repository. */
export class PaymentsService extends Context.Service<
  PaymentsService,
  {
    /** The coins of a signed-in user belong to their pair. No pair: `PaymentsNotFound`. */
    readonly ownerOf: (
      userId: UserId,
    ) => Effect.Effect<CoinOwner, PaymentsNotFound | PaymentsUnavailable>;
    /** Credits the pack once, to the ledger and to the pair's wallet. The answer's `balance` is
     * the wallet's. */
    readonly purchase: (
      owner: CoinOwner,
      signedTransaction: Redacted.Redacted<string>,
    ) => Effect.Effect<PurchaseResponse, InvalidPurchase | PaymentsNotFound | PaymentsUnavailable>;
    /** The dev stage's purchase without the App Store. The routes only serve it there. */
    readonly mockPurchase: (
      owner: CoinOwner,
      request: MockPurchaseRequest,
    ) => Effect.Effect<PurchaseResponse, InvalidPurchase | PaymentsNotFound | PaymentsUnavailable>;
    readonly purchases: (owner: CoinOwner) => Effect.Effect<PurchasesResponse, PaymentsUnavailable>;
    /** Applied once. `CONSUMPTION_REQUEST` is recorded, not answered: that needs an App Store
     * Server API key, so Apple decides the refund without it. */
    readonly notification: (
      signedPayload: Redacted.Redacted<string>,
    ) => Effect.Effect<void, InvalidPurchase | PaymentsUnavailable>;
  }
>()("@billet/backend-payments/PaymentsService") {
  static readonly layer: Layer.Layer<
    PaymentsService,
    never,
    PaymentsRepository | PaymentsConfig | PairingRepository | PairWallet | Signature.Signature
  > = Layer.effect(
    PaymentsService,
    Effect.gen(function* () {
      const repository = yield* PaymentsRepository;
      const pairing = yield* PairingRepository;
      const wallet = yield* PairWallet;
      const config = yield* PaymentsConfig;
      const services = yield* Effect.context<Signature.Signature>();

      const verified = (jws: string, allowXcode: boolean) =>
        verifySignedData(jws, { roots: config.roots, allowXcode }).pipe(
          Effect.provideContext(services),
        );

      const verifiedTransaction = Effect.fnUntraced(function* (jws: string, allowXcode: boolean) {
        const { payload, chain } = yield* verified(jws, allowXcode);
        const transaction = yield* shapeOf(Transaction, "transaction-shape")(payload);
        if (!acceptedBundleIds.includes(transaction.bundleId)) {
          return yield* new InvalidPurchase({ reason: "bundle-mismatch" });
        }
        // Only Xcode signs with its own certificate, and Apple never signs for Xcode.
        if ((chain === "xcode") !== (transaction.environment === "Xcode")) {
          return yield* new InvalidPurchase({ reason: "environment-chain-mismatch" });
        }
        return transaction;
      });

      const accepts = (environment: string) =>
        config.environments.some((accepted) => accepted === environment);

      // The ledger commits first, then the wallet. A retry after the wallet failed, or a transaction
      // sent again, reaches the wallet again: it enters `purchase:<id>` once. A duplicate stored for
      // another owner, or one refunded since, enters nothing.
      const credit = Effect.fnUntraced(function* (owner: CoinOwner, purchase: NewPurchase) {
        const credited = yield* repository.credit(purchase);
        const pairId = pairOf(owner);
        if (pairId === undefined) return credited;
        const id = purchase.originalTransactionId;
        const stored = credited.duplicate ? yield* repository.findPurchase(id) : Option.none();
        const ours =
          !credited.duplicate ||
          (Option.isSome(stored) &&
            stored.value.ownerId === owner &&
            stored.value.status === "credited");
        const balance = ours
          ? (yield* wallet.enter(pairId, {
              kind: "buy",
              id: decodeEntryId(entryIds.purchase(id)),
              ref: purchase.productId,
              coins: purchase.coins,
            })).balance
          : yield* wallet.balance(pairId);
        return { duplicate: credited.duplicate, balance };
      });

      // Before the ledger's step: once that records the notification a retry stops early, so a
      // wallet that failed would never get it. Uses the id the ledger's step will write.
      const reverseInWallet = Effect.fnUntraced(function* (
        stored: StoredPurchase,
        step: "refund" | "restore",
      ) {
        const pairId = pairOf(stored.ownerId);
        const from = step === "refund" ? "credited" : "refunded";
        if (pairId === undefined || stored.status !== from) return undefined;
        const id = stored.originalTransactionId;
        const n = stored.refunds;
        const credit =
          step === "refund"
            ? {
                kind: "refund" as const,
                id: entryIds.refund(id, n + 1),
                reverses: n === 0 ? entryIds.purchase(id) : entryIds.restore(id, n),
              }
            : {
                kind: "buy" as const,
                id: entryIds.restore(id, n),
                reverses: entryIds.refund(id, n),
              };
        return yield* wallet.enter(pairId, {
          kind: credit.kind,
          id: decodeEntryId(credit.id),
          reverses: decodeEntryId(credit.reverses),
          ref: stored.productId,
        });
      });

      // Where a request learns whose coins it touches. A demo owner has no user or pair to name.
      const ownerOf = Effect.fn("PaymentsService.ownerOf")(function* (userId: UserId) {
        yield* annotateRefs({ user: userId });
        const pairId = yield* pairing
          .findPair(userId)
          .pipe(
            Effect.mapError(
              (error) => new PaymentsUnavailable({ reason: error.reason, cause: error }),
            ),
          );
        if (Option.isNone(pairId)) return yield* new PaymentsNotFound();
        yield* annotateRefs({ pair: pairId.value });
        return decodeOwner(pairId.value);
      });

      const purchase = Effect.fn("PaymentsService.purchase")(function* (
        owner: CoinOwner,
        signedTransaction: Redacted.Redacted<string>,
      ) {
        const transaction: Transaction = yield* verifiedTransaction(
          Redacted.value(signedTransaction),
          config.devTools,
        );
        if (!accepts(transaction.environment)) {
          return yield* new InvalidPurchase({ reason: "environment-not-accepted" });
        }
        const pack = coinPackOf(transaction.productId);
        if (pack === undefined) return yield* new InvalidPurchase({ reason: "product-unknown" });
        if (transaction.type !== "Consumable") {
          return yield* new InvalidPurchase({ reason: "type-not-consumable" });
        }
        if (transaction.revocationDate !== undefined) {
          return yield* new InvalidPurchase({ reason: "transaction-revoked" });
        }
        const { duplicate, balance } = yield* credit(owner, {
          originalTransactionId: transaction.originalTransactionId,
          transactionId: transaction.transactionId,
          ownerId: owner,
          productId: pack.id,
          coins: pack.coins,
          environment: transaction.environment,
          purchasedAt: Math.max(0, Math.trunc(transaction.purchaseDate)),
          at: yield* Clock.currentTimeMillis,
        });
        return {
          transactionId: transaction.transactionId,
          productId: pack.id,
          coins: pack.coins,
          balance,
          duplicate,
        };
      });

      const mockPurchase = Effect.fn("PaymentsService.mockPurchase")(function* (
        owner: CoinOwner,
        request: MockPurchaseRequest,
      ) {
        const pack = coinPackOf(request.productId);
        if (pack === undefined) return yield* new InvalidPurchase({ reason: "product-unknown" });
        const at = yield* Clock.currentTimeMillis;
        const id = request.transactionId;
        if (request.kind === "purchase") {
          const { duplicate, balance } = yield* credit(owner, {
            originalTransactionId: id,
            transactionId: id,
            ownerId: owner,
            productId: pack.id,
            coins: pack.coins,
            environment: "Mock",
            purchasedAt: at,
            at,
          });
          return { transactionId: id, productId: pack.id, coins: pack.coins, balance, duplicate };
        }
        const stored = yield* repository.findPurchase(id);
        if (
          Option.isNone(stored) ||
          stored.value.ownerId !== owner ||
          stored.value.productId !== pack.id
        ) {
          return yield* new PaymentsNotFound();
        }
        const inWallet = yield* reverseInWallet(stored.value, "refund");
        const reversal = yield* repository.refund(stored.value, at);
        const pairId = pairOf(owner);
        const balance =
          inWallet?.balance ??
          (pairId === undefined ? reversal.balance : yield* wallet.balance(pairId));
        return {
          transactionId: id,
          productId: pack.id,
          coins: reversal.duplicate ? pack.coins : (inWallet?.coins ?? reversal.coins),
          balance,
          duplicate: reversal.duplicate,
        };
      });

      const purchases = Effect.fn("PaymentsService.purchases")((owner: CoinOwner) =>
        repository.ledger(owner).pipe(
          Effect.map(({ balance, entries }) => ({
            balance,
            entries: entries.map(({ id, kind, amount, productId, at }) => ({
              id,
              kind,
              amount,
              productId,
              at: iso(at),
            })),
          })),
        ),
      );

      const notification = Effect.fn("PaymentsService.notification")(function* (
        signedPayload: Redacted.Redacted<string>,
      ) {
        const { payload } = yield* verified(Redacted.value(signedPayload), false);
        const decoded = yield* shapeOf(Notification, "notification-shape")(payload);
        const { data } = decoded;
        if (data?.bundleId !== undefined && !acceptedBundleIds.includes(data.bundleId)) {
          return yield* new InvalidPurchase({ reason: "bundle-mismatch" });
        }
        if (yield* repository.hasNotification(decoded.notificationUUID)) return;

        const receivedAt = yield* Clock.currentTimeMillis;
        const record = (
          outcome: string,
          originalTransactionId: string | null = null,
        ): StoredNotification => ({
          notificationUuid: decoded.notificationUUID,
          type: decoded.notificationType,
          subtype: decoded.subtype ?? null,
          environment: data?.environment ?? null,
          originalTransactionId,
          outcome,
          receivedAt,
        });

        // Another stage's notifications (a sandbox one sent to dev, say) are noted, not applied.
        if (data?.environment !== undefined && !accepts(data.environment)) {
          return yield* repository.recordNotification(record("environment-not-accepted"));
        }

        const type = decoded.notificationType;
        const reverses = type === "REFUND" || type === "REVOKE";
        if (!reverses && type !== "REFUND_REVERSED") {
          return yield* repository.recordNotification(
            record(type === "CONSUMPTION_REQUEST" ? "consumption-request" : "recorded"),
          );
        }
        if (data?.signedTransactionInfo === undefined) {
          return yield* repository.recordNotification(record("no-transaction"));
        }
        const transaction = yield* verifiedTransaction(data.signedTransactionInfo, false);
        const otid = transaction.originalTransactionId;
        const stored = yield* repository.findPurchase(otid);
        if (Option.isNone(stored)) {
          return yield* repository.recordNotification(record("unknown-transaction", otid));
        }
        // A pair that has ended has no wallet left to change; the ledger still records the step.
        yield* reverseInWallet(stored.value, reverses ? "refund" : "restore").pipe(
          Effect.catchTag("PaymentsNotFound", () => Effect.void),
        );
        if (reverses) {
          const { duplicate } = yield* repository.refund(
            stored.value,
            receivedAt,
            record(stored.value.status === "credited" ? "refunded" : "duplicate", otid),
          );
          if (!duplicate) yield* Effect.logInfo("purchase refunded");
          return;
        }
        yield* repository.restore(
          stored.value,
          receivedAt,
          record(stored.value.status === "refunded" ? "restored" : "duplicate", otid),
        );
      });

      return PaymentsService.of({ ownerOf, purchase, mockPurchase, purchases, notification });
    }),
  );
}
