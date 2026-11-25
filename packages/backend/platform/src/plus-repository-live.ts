import { eq, inArray, sql } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { PaymentsUnavailable } from "@billet/backend-payments/payments-error";
import {
  PlusRepository,
  StoredParcel,
  StoredPeriod,
  StoredSubscription,
} from "@billet/backend-payments/plus-repository";
import { spanMethods } from "@billet/backend-observability/span-methods";
import { type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { plusParcels, plusPeriods, plusSubscriptions } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = (cause: unknown) =>
  new PaymentsUnavailable({ reason: "directory-unavailable", cause });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodeSubscriptions = Schema.decodeUnknownEffect(Schema.Array(StoredSubscription));
const decodePeriods = Schema.decodeUnknownEffect(Schema.Array(StoredPeriod));
const decodeParcels = Schema.decodeUnknownEffect(Schema.Array(StoredParcel));

const makePlusRepository = (db: DirectoryDatabase): PlusRepository["Service"] => {
  const subscriptionRow = (id: string) =>
    db
      .select()
      .from(plusSubscriptions)
      .where(eq(plusSubscriptions.originalTransactionId, id))
      .pipe(Effect.flatMap(decodeSubscriptions));

  const parcelRow = (id: string) =>
    db.select().from(plusParcels).where(eq(plusParcels.id, id)).pipe(Effect.flatMap(decodeParcels));

  return PlusRepository.of(
    spanMethods("PlusRepository", {
      recordsOf: (users) =>
        users.length === 0
          ? Effect.succeed({ subscriptions: [], periods: [], parcels: [] })
          : guarded(
              Effect.all({
                subscriptions: db
                  .select()
                  .from(plusSubscriptions)
                  .where(inArray(plusSubscriptions.userId, [...users]))
                  .pipe(Effect.flatMap(decodeSubscriptions)),
                periods: db
                  .select()
                  .from(plusPeriods)
                  .where(inArray(plusPeriods.userId, [...users]))
                  .pipe(Effect.flatMap(decodePeriods)),
                parcels: db
                  .select()
                  .from(plusParcels)
                  .where(inArray(plusParcels.payer, [...users]))
                  .pipe(Effect.flatMap(decodeParcels)),
              }),
            ),

      findSubscription: (id) =>
        guarded(subscriptionRow(id)).pipe(Effect.map(([row]) => Option.fromNullishOr(row))),

      // The row changes only for the account it was bound to first; another account's write
      // leaves it, and the answer shows whose it is.
      saveSubscription: (subscription) =>
        guarded(
          db
            .insert(plusSubscriptions)
            .values(subscription)
            .onConflictDoUpdate({
              target: plusSubscriptions.originalTransactionId,
              set: {
                productId: subscription.productId,
                expiresAt: subscription.expiresAt,
                autoRenew: subscription.autoRenew,
                graceUntil: subscription.graceUntil,
                revokedAt: subscription.revokedAt,
                updatedAt: subscription.updatedAt,
              },
              setWhere: eq(plusSubscriptions.userId, subscription.userId),
            })
            .pipe(Effect.andThen(subscriptionRow(subscription.originalTransactionId))),
        ).pipe(
          Effect.flatMap(([row]) =>
            row === undefined
              ? Effect.fail(unavailable("subscription-not-stored"))
              : Effect.succeed(row),
          ),
        ),

      savePeriod: (period) =>
        guarded(
          db
            .insert(plusPeriods)
            .values(period)
            .onConflictDoUpdate({
              target: plusPeriods.transactionId,
              set: { revokedAt: period.revokedAt },
            }),
        ).pipe(Effect.asVoid),

      openParcel: (parcel) =>
        guarded(
          db
            .insert(plusParcels)
            .values(parcel)
            .onConflictDoNothing()
            .pipe(Effect.andThen(parcelRow(parcel.id))),
        ).pipe(
          Effect.flatMap(([row]) =>
            row === undefined ? Effect.fail(unavailable("parcel-not-stored")) : Effect.succeed(row),
          ),
        ),

      parcelsOfTransaction: (transactionId) =>
        guarded(
          db
            .select()
            .from(plusParcels)
            .where(eq(plusParcels.transactionId, transactionId))
            .orderBy(sql`${plusParcels.id}`)
            .pipe(Effect.flatMap(decodeParcels)),
        ),

      setParcelStatus: (id, status) =>
        guarded(db.update(plusParcels).set({ status }).where(eq(plusParcels.id, id))).pipe(
          Effect.asVoid,
        ),
    }),
  );
};

/** Build it once per request, as `openDirectoryDatabase` asks. */
export const PlusRepositoryLive = (binding: D1Database): Layer.Layer<PlusRepository> =>
  Layer.effect(PlusRepository, Effect.map(openDirectoryDatabase(binding), makePlusRepository));
