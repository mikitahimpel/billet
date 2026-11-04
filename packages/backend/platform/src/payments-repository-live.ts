import { and, asc, eq, sql } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { PaymentsUnavailable } from "@billet/backend-payments/payments-error";
import {
  entryIds,
  PaymentsRepository,
  type StampOwner,
  type StoredNotification,
  StoredPurchase,
  type StoredPurchase as Purchase,
  StoredStampEntry,
} from "@billet/backend-payments/payments-repository";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { appStoreNotifications, purchases, stampLedger } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = () => new PaymentsUnavailable({ reason: "directory-unavailable" });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodePurchases = Schema.decodeUnknownEffect(Schema.Array(StoredPurchase));
const decodeEntries = Schema.decodeUnknownEffect(Schema.Array(StoredStampEntry));
// A batch returns rows as stored, keyed by column name rather than by Drizzle field.
const decodeBalance = Schema.decodeUnknownEffect(
  Schema.Array(Schema.Struct({ balance: Schema.Number })),
);
const decodeAmounts = Schema.decodeUnknownEffect(
  Schema.Array(Schema.Struct({ amount: Schema.Number })),
);

const balanceOf = (rows: unknown) =>
  decodeBalance(rows).pipe(Effect.map(([row]) => Math.max(0, row?.balance ?? 0)));

const makePaymentsRepository = (db: DirectoryDatabase): PaymentsRepository["Service"] => {
  const balanceQuery = (owner: StampOwner) =>
    db
      .select({ balance: sql<number>`coalesce(sum(${stampLedger.amount}), 0)`.as("balance") })
      .from(stampLedger)
      .where(eq(stampLedger.ownerId, owner));

  const noted = (notification: StoredNotification | undefined) =>
    notification === undefined
      ? []
      : [db.insert(appStoreNotifications).values(notification).onConflictDoNothing()];

  // The purchase as the caller read it: a step applies only if nobody moved it on since.
  const asRead = (purchase: Purchase, status: Purchase["status"]) =>
    and(
      eq(purchases.originalTransactionId, purchase.originalTransactionId),
      eq(purchases.status, status),
      eq(purchases.refunds, purchase.refunds),
    );

  return PaymentsRepository.of({
    // The ledger entry is written only for the owner the stored purchase names, so a transaction
    // sent again from another pair never credits that pair.
    credit: (purchase) =>
      guarded(
        atomically(db, [
          db
            .insert(purchases)
            .values({
              originalTransactionId: purchase.originalTransactionId,
              transactionId: purchase.transactionId,
              ownerId: purchase.ownerId,
              productId: purchase.productId,
              stamps: purchase.stamps,
              environment: purchase.environment,
              status: "credited",
              refunds: 0,
              flagged: 0,
              purchasedAt: purchase.purchasedAt,
              createdAt: purchase.at,
              updatedAt: purchase.at,
            })
            .onConflictDoNothing()
            .returning({ id: purchases.originalTransactionId }),
          db.insert(stampLedger).select((qb) =>
            qb
              .select({
                id: sql<string>`${entryIds.purchase(purchase.originalTransactionId)}`.as("id"),
                ownerId: purchases.ownerId,
                kind: sql<string>`'purchase'`.as("kind"),
                amount: purchases.stamps,
                productId: purchases.productId,
                originalTransactionId: purchases.originalTransactionId,
                at: sql<number>`${purchase.at}`.as("at"),
              })
              .from(purchases)
              .where(
                and(
                  eq(purchases.originalTransactionId, purchase.originalTransactionId),
                  eq(purchases.ownerId, purchase.ownerId),
                  sql`not exists (select 1 from ${stampLedger} where ${stampLedger.id} = ${entryIds.purchase(purchase.originalTransactionId)})`,
                ),
              ),
          ),
          balanceQuery(purchase.ownerId),
        ]).pipe(
          Effect.flatMap((results) =>
            Effect.map(balanceOf(results[2]), (balance) => ({
              duplicate: (results[0]?.length ?? 0) === 0,
              balance,
            })),
          ),
        ),
      ),

    findPurchase: (id) =>
      guarded(
        db
          .select()
          .from(purchases)
          .where(eq(purchases.originalTransactionId, id))
          .pipe(Effect.flatMap(decodePurchases)),
      ).pipe(Effect.map(([row]) => Option.fromNullishOr(row))),

    // At most the owner's balance comes back, so it never goes below 0. Taking less than the
    // pack flags the purchase.
    refund: (purchase, at, notification) => {
      const id = entryIds.refund(purchase.originalTransactionId, purchase.refunds + 1);
      return guarded(
        atomically(db, [
          db
            .insert(stampLedger)
            .select((qb) =>
              qb
                .select({
                  id: sql<string>`${id}`.as("id"),
                  ownerId: purchases.ownerId,
                  kind: sql<string>`'refund'`.as("kind"),
                  amount:
                    sql<number>`-min(${purchases.stamps}, max(0, (select coalesce(sum(${stampLedger.amount}), 0) from ${stampLedger} where ${stampLedger.ownerId} = ${purchases.ownerId})))`.as(
                      "amount",
                    ),
                  productId: purchases.productId,
                  originalTransactionId: purchases.originalTransactionId,
                  at: sql<number>`${at}`.as("at"),
                })
                .from(purchases)
                .where(asRead(purchase, "credited")),
            )
            .returning({ amount: stampLedger.amount }),
          db
            .update(purchases)
            .set({
              status: "refunded",
              refunds: purchase.refunds + 1,
              flagged: sql`case when (select -${stampLedger.amount} from ${stampLedger} where ${stampLedger.id} = ${id}) < ${purchases.stamps} then 1 else ${purchases.flagged} end`,
              updatedAt: at,
            })
            .where(asRead(purchase, "credited")),
          ...noted(notification),
          balanceQuery(purchase.ownerId),
        ]).pipe(
          Effect.flatMap((results) =>
            Effect.all([decodeAmounts(results[0]), balanceOf(results.at(-1))]),
          ),
          Effect.map(([[written], balance]) => ({
            duplicate: written === undefined,
            stamps: written === undefined ? 0 : -written.amount,
            balance,
          })),
        ),
      );
    },

    // What the last refund took comes back, under its own entry.
    restore: (purchase, at, notification) => {
      const refundId = entryIds.refund(purchase.originalTransactionId, purchase.refunds);
      return guarded(
        atomically(db, [
          db
            .insert(stampLedger)
            .select((qb) =>
              qb
                .select({
                  id: sql<string>`${entryIds.restore(purchase.originalTransactionId, purchase.refunds)}`.as(
                    "id",
                  ),
                  ownerId: purchases.ownerId,
                  kind: sql<string>`'purchase'`.as("kind"),
                  amount:
                    sql<number>`coalesce((select -${stampLedger.amount} from ${stampLedger} where ${stampLedger.id} = ${refundId}), 0)`.as(
                      "amount",
                    ),
                  productId: purchases.productId,
                  originalTransactionId: purchases.originalTransactionId,
                  at: sql<number>`${at}`.as("at"),
                })
                .from(purchases)
                .where(asRead(purchase, "refunded")),
            )
            .returning({ amount: stampLedger.amount }),
          db
            .update(purchases)
            .set({ status: "credited", updatedAt: at })
            .where(asRead(purchase, "refunded")),
          ...noted(notification),
          balanceQuery(purchase.ownerId),
        ]).pipe(
          Effect.flatMap((results) =>
            Effect.all([decodeAmounts(results[0]), balanceOf(results.at(-1))]),
          ),
          Effect.map(([[written], balance]) => ({
            duplicate: written === undefined,
            stamps: written?.amount ?? 0,
            balance,
          })),
        ),
      );
    },

    hasNotification: (uuid) =>
      guarded(
        db
          .select({ uuid: appStoreNotifications.notificationUuid })
          .from(appStoreNotifications)
          .where(eq(appStoreNotifications.notificationUuid, uuid)),
      ).pipe(Effect.map((rows) => rows.length > 0)),

    recordNotification: (notification) =>
      guarded(db.insert(appStoreNotifications).values(notification).onConflictDoNothing()).pipe(
        Effect.asVoid,
      ),

    ledger: (owner) =>
      guarded(
        Effect.all([
          db
            .select()
            .from(stampLedger)
            .where(eq(stampLedger.ownerId, owner))
            .orderBy(asc(stampLedger.at), asc(stampLedger.id))
            .pipe(Effect.flatMap(decodeEntries)),
          balanceQuery(owner).pipe(Effect.flatMap(balanceOf)),
        ]),
      ).pipe(Effect.map(([entries, balance]) => ({ entries, balance }))),
  });
};

/** `PaymentsRepository` on the D1 directory. Build it once per request, as `openDirectoryDatabase` asks. */
export const PaymentsRepositoryLive = (binding: D1Database): Layer.Layer<PaymentsRepository> =>
  Layer.effect(
    PaymentsRepository,
    Effect.map(openDirectoryDatabase(binding), makePaymentsRepository),
  );
