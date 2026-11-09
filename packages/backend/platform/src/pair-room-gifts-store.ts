import { and, eq } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { GiftWish, Loves } from "@billet/contracts-http-api/gifts";
import { GiftsStore, StoredGiftPlan, type GiftWrite } from "@billet/backend-pair-room/gifts";
import { UserId } from "@billet/contracts-domain/ids";
import { RoomDb } from "./pair-room-sqlite-store.ts";
import { giftLoves, giftPlan, giftWish } from "./room-schema.ts";

const decodeWish = Schema.decodeUnknownOption(GiftWish);
const decodePlan = Schema.decodeUnknownOption(StoredGiftPlan);
const decodeUser = Schema.decodeUnknownOption(UserId);
const LovesJson = Schema.fromJsonString(Loves);
const encodeLoves = Schema.encodeSync(LovesJson);
const decodeLoves = Schema.decodeOption(LovesJson);

const wishValues = (wish: GiftWish): typeof giftWish.$inferInsert => ({
  id: wish.id,
  owner: wish.owner,
  title: wish.title,
  link: wish.link,
  price: wish.price,
  note: wish.note,
  mostWanted: wish.mostWanted ? 1 : 0,
  occasionTitle: wish.occasion?.title ?? null,
  occasionDate: wish.occasion?.date ?? null,
  addedAt: wish.addedAt,
  receivedAt: wish.receivedAt ?? null,
  giftedBy: wish.giftedBy ?? null,
});

/** A row this code cannot read, such as one a newer build wrote, is left out. */
const wishFrom = (row: typeof giftWish.$inferSelect) =>
  decodeWish({
    id: row.id,
    owner: row.owner,
    title: row.title,
    link: row.link,
    price: row.price,
    note: row.note,
    mostWanted: row.mostWanted === 1,
    ...(row.occasionTitle === null || row.occasionDate === null
      ? {}
      : { occasion: { title: row.occasionTitle, date: row.occasionDate } }),
    addedAt: row.addedAt,
    ...(row.receivedAt === null ? {} : { receivedAt: row.receivedAt }),
    ...(row.giftedBy === null ? {} : { giftedBy: row.giftedBy }),
  });

export const SqliteGiftsStore = Layer.effect(
  GiftsStore,
  Effect.gen(function* () {
    const db = yield* RoomDb;

    type Tx = Parameters<Parameters<typeof db.transaction>[0]>[0];

    const write = (tx: Tx, write: GiftWrite) => {
      switch (write._tag) {
        case "PutWish": {
          const values = wishValues(write.wish);
          return tx
            .insert(giftWish)
            .values(values)
            .onConflictDoUpdate({ target: giftWish.id, set: values });
        }
        case "DropWish":
          return tx.delete(giftWish).where(eq(giftWish.id, write.id));
        case "PutPlan": {
          const { wish, giver, stage } = write.plan;
          return tx
            .insert(giftPlan)
            .values({ wishId: wish, giver, stage })
            .onConflictDoUpdate({ target: [giftPlan.wishId, giftPlan.giver], set: { stage } });
        }
        case "DropPlans":
          return tx
            .delete(giftPlan)
            .where(
              and(
                eq(giftPlan.wishId, write.wish),
                write.giver === undefined ? undefined : eq(giftPlan.giver, write.giver),
              ),
            );
        case "PutLoves": {
          const body = encodeLoves(write.loves);
          return tx
            .insert(giftLoves)
            .values({ user: write.user, body })
            .onConflictDoUpdate({ target: giftLoves.user, set: { body } });
        }
      }
    };

    return GiftsStore.of({
      load: Effect.all([
        db.select().from(giftWish),
        db.select().from(giftPlan),
        db.select().from(giftLoves),
      ]).pipe(
        Effect.map(([wishes, plans, loves]) => ({
          wishes: wishes.flatMap((row) => Option.toArray(wishFrom(row))),
          plans: plans.flatMap(({ wishId, giver, stage }) =>
            Option.toArray(decodePlan({ wish: wishId, giver, stage })),
          ),
          loves: loves.flatMap(({ user, body }) =>
            Option.toArray(Option.all({ user: decodeUser(user), loves: decodeLoves(body) })),
          ),
        })),
        Effect.orDie,
      ),
      apply: (writes) =>
        db
          .transaction((tx) => Effect.forEach(writes, (w) => write(tx, w), { discard: true }))
          .pipe(Effect.asVoid, Effect.orDie),
      forget: db
        .transaction((tx) =>
          Effect.gen(function* () {
            yield* tx.delete(giftPlan);
            yield* tx.delete(giftWish);
            yield* tx.delete(giftLoves);
          }),
        )
        .pipe(Effect.asVoid, Effect.orDie),
    });
  }),
);
