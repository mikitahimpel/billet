import { Clock, Context, Effect, Layer, Option, Redacted, Schema } from "effect";
import type { Signature } from "effect/crypto";
import { CoinEntryId } from "@billet/contracts-domain/coins";
import { acceptedBundleIds } from "@billet/contracts-domain/coin-packs";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import {
  fitsParcel,
  type ParcelOffer,
  parcelChoices,
  plusProductFor,
  plusProductOf,
  priceOfParcelOffer,
} from "@billet/contracts-domain/plus";
import type {
  MockPlusRequest,
  OpenParcelRequest,
  OpenParcelResponse,
  PlusResponse,
} from "@billet/contracts-http-api/plus";
import type { ShopResponse } from "@billet/contracts-http-api/shop";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { verifySignedData } from "./app-store-signed-data.ts";
import { PairWallet } from "./pair-wallet.ts";
import { PaymentsConfig } from "./payments-config.ts";
import {
  InvalidPurchase,
  ParcelOpened,
  ParcelRefused,
  PaymentsNotFound,
  PaymentsUnavailable,
  PieceOwned,
  SubscriptionTaken,
} from "./payments-error.ts";
import { PlusRepository, type StoredParcel, type StoredSubscription } from "./plus-repository.ts";
import { addMonths, pairPlus, waitingParcels } from "./plus-rules.ts";

/** The fields of a subscription's `JWSTransactionDecodedPayload` that matter here. */
const SubscriptionTransaction = Schema.Struct({
  transactionId: Schema.String.check(Schema.isNonEmpty()),
  originalTransactionId: Schema.String.check(Schema.isNonEmpty()),
  bundleId: Schema.String,
  productId: Schema.String,
  type: Schema.String,
  environment: Schema.String,
  purchaseDate: Schema.Number,
  expiresDate: Schema.Number,
  revocationDate: Schema.optional(Schema.Number),
  inAppOwnershipType: Schema.optional(Schema.String),
});
type SubscriptionTransaction = typeof SubscriptionTransaction.Type;

/** The fields of `JWSRenewalInfoDecodedPayload` that matter here. */
const RenewalInfo = Schema.Struct({
  originalTransactionId: Schema.String,
  autoRenewStatus: Schema.optional(Schema.Number),
  gracePeriodExpiresDate: Schema.optional(Schema.Number),
});
type RenewalInfo = typeof RenewalInfo.Type;

const shapeOf =
  <S extends Schema.Top & { readonly DecodingServices: never }>(schema: S, reason: string) =>
  (input: unknown) =>
    Schema.decodeUnknownEffect(schema)(input).pipe(
      Effect.mapError(() => new InvalidPurchase({ reason })),
    );

const decodeEntryId = Schema.decodeSync(CoinEntryId);

/** How many days Apple retries a failed renewal while Plus carries on (set in App Store Connect). */
const graceDays = 16;
const dayMillis = 86_400_000;

const idOf = (offer: ParcelOffer): string => {
  switch (offer._tag) {
    case "Ink":
      return offer.ink;
    case "Item":
      return offer.item;
    case "Postage":
      return offer.postage;
  }
};

const owns = (shop: ShopResponse, offer: ParcelOffer): boolean => {
  switch (offer._tag) {
    case "Ink":
      return shop.inks.includes(offer.ink);
    case "Item":
      return shop.items.includes(offer.item);
    case "Postage":
      return (shop.postage ?? []).includes(offer.postage);
  }
};

const sameOffer = (stored: StoredParcel, offer: ParcelOffer) =>
  stored.offer === JSON.stringify(offer);

export type PlusFailure = InvalidPurchase | PaymentsNotFound | PaymentsUnavailable;

/** What a notification about a Plus subscription did, for the notifications record. */
export interface PlusNotificationOutcome {
  readonly outcome: string;
  readonly originalTransactionId: string;
}

/** Ourio Plus: whose subscription it is, what each paid month brought, and its parcels. */
export class PlusService extends Context.Service<
  PlusService,
  {
    readonly view: (userId: UserId, pairId: PairId) => Effect.Effect<PlusResponse, PlusFailure>;
    /** Binds the subscription to the caller the first time; another caller is refused. */
    readonly subscribe: (
      userId: UserId,
      pairId: PairId,
      signedTransaction: Redacted.Redacted<string>,
      signedRenewalInfo: Redacted.Redacted<string> | undefined,
    ) => Effect.Effect<PlusResponse, PlusFailure | SubscriptionTaken>;
    /** The dev stage's App Store. The routes only serve it there. */
    readonly mock: (
      userId: UserId,
      pairId: PairId,
      request: MockPlusRequest,
    ) => Effect.Effect<PlusResponse, PlusFailure | SubscriptionTaken>;
    readonly openParcel: (
      userId: UserId,
      pairId: PairId,
      request: OpenParcelRequest,
    ) => Effect.Effect<OpenParcelResponse, PlusFailure | ParcelOpened | ParcelRefused | PieceOwned>;
    /** Undefined when `transaction` is not a Plus product, so the coin path handles it. The
     * transaction's signature is checked already. */
    readonly notification: (
      type: string,
      subtype: string | undefined,
      transaction: unknown,
      signedRenewalInfo: string | undefined,
    ) => Effect.Effect<PlusNotificationOutcome | undefined, InvalidPurchase | PaymentsUnavailable>;
  }
>()("@billet/backend-payments/PlusService") {
  static readonly layer: Layer.Layer<
    PlusService,
    never,
    PlusRepository | PaymentsConfig | PairingRepository | PairWallet | Signature.Signature
  > = Layer.effect(
    PlusService,
    Effect.gen(function* () {
      const repository = yield* PlusRepository;
      const pairing = yield* PairingRepository;
      const wallet = yield* PairWallet;
      const config = yield* PaymentsConfig;
      const services = yield* Effect.context<Signature.Signature>();

      const accepts = (environment: string) =>
        config.environments.some((accepted) => accepted === environment);

      const verifiedPayload = (jws: string, allowXcode: boolean) =>
        verifySignedData(jws, { roots: config.roots, allowXcode }).pipe(
          Effect.provideContext(services),
        );

      const checkedTransaction = Effect.fnUntraced(function* (
        payload: unknown,
        chain: "apple" | "xcode",
      ) {
        const transaction = yield* shapeOf(SubscriptionTransaction, "transaction-shape")(payload);
        if (!acceptedBundleIds.includes(transaction.bundleId)) {
          return yield* new InvalidPurchase({ reason: "bundle-mismatch" });
        }
        if ((chain === "xcode") !== (transaction.environment === "Xcode")) {
          return yield* new InvalidPurchase({ reason: "environment-chain-mismatch" });
        }
        if (plusProductOf(transaction.productId) === undefined) {
          return yield* new InvalidPurchase({ reason: "product-unknown" });
        }
        if (transaction.type !== "Auto-Renewable Subscription") {
          return yield* new InvalidPurchase({ reason: "type-not-subscription" });
        }
        // Family Sharing is off for Plus; a shared copy would reach people outside the pair.
        if (transaction.inAppOwnershipType === "FAMILY_SHARED") {
          return yield* new InvalidPurchase({ reason: "family-shared" });
        }
        return transaction;
      });

      const renewalOf = Effect.fnUntraced(function* (jws: string | undefined, allowXcode: boolean) {
        if (jws === undefined) return undefined;
        const { payload } = yield* verifiedPayload(jws, allowXcode);
        return yield* shapeOf(RenewalInfo, "renewal-shape")(payload);
      });

      const unavailable = (reason: string) => (cause: unknown) =>
        new PaymentsUnavailable({ reason, cause });

      const membersOf = (userId: UserId, pairId: PairId) =>
        pairing.findMembers(pairId).pipe(
          Effect.mapError(unavailable("pairing-unavailable")),
          Effect.map((members) => (members.includes(userId) ? members : [userId])),
        );

      const view = Effect.fn("PlusService.view")(function* (userId: UserId, pairId: PairId) {
        const members = yield* membersOf(userId, pairId);
        const records = yield* repository.recordsOf(members);
        const shop = yield* wallet.shop(pairId);
        const now = yield* Clock.currentTimeMillis;
        const plus = pairPlus(
          {
            caller: userId,
            members,
            subscriptions: records.subscriptions,
            periods: records.periods,
            opened: new Set(records.parcels.map(({ id }) => id)),
          },
          now,
        );
        const choicesLeft = parcelChoices.filter((offer) => !owns(shop, offer)).length;
        return { ...plus, choicesLeft } satisfies PlusResponse;
      });

      // A refunded month takes back what its parcels became: the piece stays, its coin price
      // is owed, as a refunded pack's coins are. Each step is once per parcel id, so a retried
      // notification moves nothing twice.
      const reverseParcels = Effect.fnUntraced(function* (
        transactionId: string,
        step: "refund" | "restore",
      ) {
        const parcels = yield* repository.parcelsOfTransaction(transactionId);
        for (const parcel of parcels) {
          const from = step === "refund" ? "opened" : "refunded";
          if (parcel.status !== from) continue;
          yield* wallet
            .enter(parcel.pairId, {
              kind: step === "refund" ? "refund" : "purchase",
              id: decodeEntryId(`${step}:${parcel.id}`),
              ref: parcel.id,
              coins: parcel.price,
            })
            .pipe(Effect.catchTag("PaymentsNotFound", () => Effect.void));
          yield* repository.setParcelStatus(parcel.id, step === "refund" ? "refunded" : "opened");
        }
      });

      const savePeriodOf = (userId: UserId, transaction: SubscriptionTransaction, at: number) =>
        repository.savePeriod({
          transactionId: transaction.transactionId,
          originalTransactionId: transaction.originalTransactionId,
          userId,
          productId: transaction.productId,
          purchasedAt: Math.max(0, Math.trunc(transaction.purchaseDate)),
          expiresAt: Math.max(0, Math.trunc(transaction.expiresDate)),
          revokedAt: transaction.revocationDate === undefined ? null : at,
        });

      /** The subscription as a new transaction and renewal info leave it. */
      const updated = (
        stored: StoredSubscription,
        transaction: SubscriptionTransaction | undefined,
        renewal: RenewalInfo | undefined,
        at: number,
      ): StoredSubscription => ({
        ...stored,
        productId: transaction?.productId ?? stored.productId,
        expiresAt: Math.max(stored.expiresAt, Math.trunc(transaction?.expiresDate ?? 0)),
        autoRenew:
          renewal?.autoRenewStatus === undefined ? stored.autoRenew : renewal.autoRenewStatus === 1,
        graceUntil: renewal?.gracePeriodExpiresDate ?? stored.graceUntil,
        updatedAt: at,
      });

      const bind = Effect.fnUntraced(function* (
        userId: UserId,
        transaction: SubscriptionTransaction,
        renewal: RenewalInfo | undefined,
      ) {
        const at = yield* Clock.currentTimeMillis;
        const existing = yield* repository.findSubscription(transaction.originalTransactionId);
        if (Option.isSome(existing) && existing.value.userId !== userId) {
          return yield* new SubscriptionTaken();
        }
        const base: StoredSubscription = Option.getOrElse(existing, () => ({
          originalTransactionId: transaction.originalTransactionId,
          userId,
          productId: transaction.productId,
          environment: transaction.environment,
          expiresAt: 0,
          autoRenew: true,
          graceUntil: null,
          revokedAt: null,
          createdAt: at,
          updatedAt: at,
        }));
        const stored = yield* repository.saveSubscription(updated(base, transaction, renewal, at));
        if (stored.userId !== userId) return yield* new SubscriptionTaken();
        yield* savePeriodOf(userId, transaction, at);
      });

      const subscribe = Effect.fn("PlusService.subscribe")(function* (
        userId: UserId,
        pairId: PairId,
        signedTransaction: Redacted.Redacted<string>,
        signedRenewalInfo: Redacted.Redacted<string> | undefined,
      ) {
        const { payload, chain } = yield* verifiedPayload(
          Redacted.value(signedTransaction),
          config.devTools,
        );
        const transaction = yield* checkedTransaction(payload, chain);
        if (!accepts(transaction.environment)) {
          return yield* new InvalidPurchase({ reason: "environment-not-accepted" });
        }
        if (transaction.revocationDate !== undefined) {
          return yield* new InvalidPurchase({ reason: "transaction-revoked" });
        }
        const renewal = yield* renewalOf(
          signedRenewalInfo === undefined ? undefined : Redacted.value(signedRenewalInfo),
          config.devTools,
        );
        if (
          renewal !== undefined &&
          renewal.originalTransactionId !== transaction.originalTransactionId
        ) {
          return yield* new InvalidPurchase({ reason: "renewal-mismatch" });
        }
        yield* bind(userId, transaction, renewal);
        return yield* view(userId, pairId);
      });

      const mock = Effect.fn("PlusService.mock")(function* (
        userId: UserId,
        pairId: PairId,
        request: MockPlusRequest,
      ) {
        const now = yield* Clock.currentTimeMillis;
        const product = plusProductFor(request.plan);
        const otid = request.transactionId;
        const records = yield* repository.recordsOf([userId]);
        const periods = records.periods
          .filter((period) => period.originalTransactionId === otid)
          .toSorted((a, b) => a.purchasedAt - b.purchasedAt);
        const transaction = (transactionId: string): SubscriptionTransaction => ({
          transactionId,
          originalTransactionId: otid,
          bundleId: acceptedBundleIds[0] ?? "",
          productId: product.id,
          type: "Auto-Renewable Subscription",
          environment: "Mock",
          purchaseDate: now,
          expiresDate: addMonths(now, product.parcels),
        });
        if (request.kind === "subscribe") {
          yield* bind(userId, transaction(otid), {
            originalTransactionId: otid,
            autoRenewStatus: 1,
          });
          return yield* view(userId, pairId);
        }
        const found = yield* repository.findSubscription(otid);
        if (Option.isNone(found) || found.value.userId !== userId) {
          return yield* new PaymentsNotFound();
        }
        const stored = found.value;
        const save = (change: Partial<StoredSubscription>) =>
          repository.saveSubscription({ ...stored, ...change, updatedAt: now });
        switch (request.kind) {
          case "renew":
            yield* bind(userId, transaction(`${otid}-r${periods.length}`), {
              originalTransactionId: otid,
              autoRenewStatus: 1,
            });
            yield* save({
              expiresAt: addMonths(now, product.parcels),
              autoRenew: true,
              graceUntil: null,
            });
            break;
          case "cancel":
            yield* save({ autoRenew: false });
            break;
          case "fail":
            yield* save({ expiresAt: now, graceUntil: now + graceDays * dayMillis });
            break;
          case "expire":
            yield* save({ expiresAt: now, autoRenew: false, graceUntil: null });
            break;
          case "refund": {
            const last = periods.at(-1);
            if (last === undefined) return yield* new PaymentsNotFound();
            yield* reverseParcels(last.transactionId, "refund");
            yield* repository.savePeriod({ ...last, revokedAt: now });
            break;
          }
        }
        return yield* view(userId, pairId);
      });

      const openParcel = Effect.fn("PlusService.openParcel")(function* (
        userId: UserId,
        pairId: PairId,
        request: OpenParcelRequest,
      ) {
        const members = yield* membersOf(userId, pairId);
        const records = yield* repository.recordsOf(members);
        const earlier = records.parcels.find(({ id }) => id === request.parcel);
        const grantAndAnswer = (offer: ParcelOffer) =>
          Effect.gen(function* () {
            const shop = yield* wallet.grant(pairId, offer);
            return { plus: yield* view(userId, pairId), shop };
          });
        // Opened already: the same choice answers again (and gives the piece again, which a
        // retry after the room failed needs); another choice is refused.
        if (earlier !== undefined) {
          if (!sameOffer(earlier, request.offer) || earlier.pairId !== pairId) {
            return yield* new ParcelOpened();
          }
          return yield* grantAndAnswer(request.offer);
        }
        const now = yield* Clock.currentTimeMillis;
        const waiting = waitingParcels(
          {
            caller: userId,
            members,
            subscriptions: records.subscriptions,
            periods: records.periods,
            opened: new Set(records.parcels.map(({ id }) => id)),
          },
          now,
        ).find(({ id }) => id === request.parcel);
        if (waiting === undefined) return yield* new PaymentsNotFound();
        const price = priceOfParcelOffer(request.offer);
        if (price === undefined || !fitsParcel(request.offer)) {
          return yield* new ParcelRefused({
            reason: price === undefined ? "not-sold" : "too-dear",
          });
        }
        if (owns(yield* wallet.shop(pairId), request.offer)) {
          return yield* new PieceOwned({ itemId: idOf(request.offer) });
        }
        const stored = yield* repository.openParcel({
          id: waiting.id,
          payer: waiting.payer,
          transactionId: waiting.transactionId,
          pairId,
          offer: JSON.stringify(request.offer),
          price,
          openedBy: userId,
          openedAt: now,
          status: "opened",
        });
        if (!sameOffer(stored, request.offer)) return yield* new ParcelOpened();
        yield* Effect.logInfo("parcel opened");
        return yield* grantAndAnswer(request.offer);
      });

      const notification = Effect.fn("PlusService.notification")(function* (
        type: string,
        subtype: string | undefined,
        payload: unknown,
        signedRenewalInfo: string | undefined,
      ) {
        const peek = Schema.decodeUnknownOption(Schema.Struct({ productId: Schema.String }))(
          payload,
        );
        if (Option.isNone(peek) || plusProductOf(peek.value.productId) === undefined) {
          return undefined;
        }
        const transaction = yield* checkedTransaction(payload, "apple");
        const otid = transaction.originalTransactionId;
        const outcome = (name: string): PlusNotificationOutcome => ({
          outcome: `plus-${name}`,
          originalTransactionId: otid,
        });
        if (!accepts(transaction.environment)) return outcome("environment-not-accepted");
        // Bound by the app's first `POST /v1/plus/subscribe`, which carries the same
        // transaction; until then there is no account to give it to.
        const found = yield* repository.findSubscription(otid);
        if (Option.isNone(found)) return outcome("unknown-subscription");
        const stored = found.value;
        const at = yield* Clock.currentTimeMillis;
        const renewal = yield* renewalOf(signedRenewalInfo, false);

        switch (type) {
          case "REFUND":
          case "REVOKE": {
            yield* reverseParcels(transaction.transactionId, "refund");
            yield* savePeriodOf(stored.userId, { ...transaction, revocationDate: at }, at);
            if (type === "REVOKE") {
              yield* repository.saveSubscription({ ...stored, revokedAt: at, updatedAt: at });
            }
            return outcome("refunded");
          }
          case "REFUND_REVERSED": {
            const { revocationDate: _, ...restored } = transaction;
            yield* savePeriodOf(stored.userId, restored, at);
            yield* reverseParcels(transaction.transactionId, "restore");
            return outcome("restored");
          }
          default: {
            const autoRenew =
              subtype === "AUTO_RENEW_DISABLED" || type === "EXPIRED"
                ? false
                : subtype === "AUTO_RENEW_ENABLED"
                  ? true
                  : undefined;
            const clearsGrace =
              type === "DID_RENEW" || type === "SUBSCRIBED" || type === "GRACE_PERIOD_EXPIRED";
            const next = updated(stored, transaction, renewal, at);
            yield* repository.saveSubscription({
              ...next,
              autoRenew: autoRenew ?? next.autoRenew,
              graceUntil:
                clearsGrace && renewal?.gracePeriodExpiresDate === undefined
                  ? null
                  : next.graceUntil,
            });
            if (transaction.revocationDate === undefined) {
              yield* savePeriodOf(stored.userId, transaction, at);
            }
            return outcome(type.toLowerCase().replaceAll("_", "-"));
          }
        }
      });

      return PlusService.of({ view, subscribe, mock, openParcel, notification });
    }),
  );
}
