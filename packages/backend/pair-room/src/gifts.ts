import { Clock, Context, Effect, Layer, Schema, Semaphore } from "effect";
import { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import {
  GiftStage,
  GiftWish,
  Loves,
  GiftsResponse,
  SaveGiftWishRequest,
} from "@billet/contracts-http-api/gifts";
import { RoomStore } from "./room-store.ts";

/** A plan as the room stores it: with its giver, whom only the giver's own view ever shows. */
export const StoredGiftPlan = Schema.Struct({
  wish: IdempotencyKey,
  giver: UserId,
  stage: GiftStage,
});
export type StoredGiftPlan = typeof StoredGiftPlan.Type;

export interface GiftRows {
  readonly wishes: ReadonlyArray<GiftWish>;
  readonly plans: ReadonlyArray<StoredGiftPlan>;
  readonly loves: ReadonlyArray<{ readonly user: UserId; readonly loves: Loves }>;
}

/** One change to the gift tables. `DropPlans` without `giver` drops every plan for the wish. */
export type GiftWrite =
  | { readonly _tag: "PutWish"; readonly wish: GiftWish }
  | { readonly _tag: "DropWish"; readonly id: IdempotencyKey }
  | { readonly _tag: "PutPlan"; readonly plan: StoredGiftPlan }
  | { readonly _tag: "DropPlans"; readonly wish: IdempotencyKey; readonly giver?: UserId }
  | { readonly _tag: "PutLoves"; readonly user: UserId; readonly loves: Loves };

export const GiftCommand = Schema.TaggedUnion({
  View: {},
  SaveWish: { wish: SaveGiftWishRequest },
  DeleteWish: { id: IdempotencyKey },
  SetPlan: { wish: IdempotencyKey, stage: Schema.optionalKey(GiftStage) },
  MarkReceived: { wish: IdempotencyKey, received: Schema.Boolean },
  SaveLoves: { loves: Loves },
});
export type GiftCommand = typeof GiftCommand.Type;

/**
 * Why a change was refused. `NotFound`: no such wish. `NotAllowed`: a wish that is not the
 * caller's to change, or their own to plan. `Taken`: the partner's other plan holds it, which can
 * only happen with more than two people. `NotOpen`: the room has no members yet.
 */
export const GiftRefusal = Schema.Literals(["NotFound", "NotAllowed", "Taken", "NotOpen"]);
export type GiftRefusal = typeof GiftRefusal.Type;

/** Decided changes, or a refusal. */
export type GiftDecision =
  | { readonly _tag: "Done"; readonly writes: ReadonlyArray<GiftWrite> }
  | { readonly _tag: "Refused"; readonly reason: GiftRefusal };

const done = (...writes: ReadonlyArray<GiftWrite>): GiftDecision => ({ _tag: "Done", writes });
const refused = (reason: GiftRefusal): GiftDecision => ({ _tag: "Refused", reason });

/** What `by` changes with `command`. Every rule about who may change what is here. */
export const decideGift = (
  rows: GiftRows,
  by: UserId,
  command: GiftCommand,
  at: EpochMillis,
): GiftDecision => {
  const wishOf = (id: IdempotencyKey) => rows.wishes.find((wish) => wish.id === id);
  switch (command._tag) {
    case "View":
      return done();
    case "SaveWish": {
      const { id, ...fields } = command.wish;
      const existing = wishOf(id);
      if (existing === undefined) {
        return done({ _tag: "PutWish", wish: { id, owner: by, ...fields, addedAt: at } });
      }
      if (existing.owner !== by) return refused("NotAllowed");
      const { receivedAt, giftedBy } = existing;
      return done({
        _tag: "PutWish",
        wish: {
          id,
          owner: existing.owner,
          ...fields,
          addedAt: existing.addedAt,
          ...(receivedAt === undefined ? {} : { receivedAt }),
          ...(giftedBy === undefined ? {} : { giftedBy }),
        },
      });
    }
    case "DeleteWish": {
      const existing = wishOf(command.id);
      if (existing === undefined) return refused("NotFound");
      if (existing.owner !== by) return refused("NotAllowed");
      return done({ _tag: "DropWish", id: command.id }, { _tag: "DropPlans", wish: command.id });
    }
    case "SetPlan": {
      const wish = wishOf(command.wish);
      if (wish === undefined) return refused("NotFound");
      if (wish.owner === by || wish.receivedAt !== undefined) return refused("NotAllowed");
      if (command.stage === undefined) return done({ _tag: "DropPlans", wish: wish.id, giver: by });
      if (rows.plans.some((plan) => plan.wish === wish.id && plan.giver !== by)) {
        return refused("Taken");
      }
      return done({ _tag: "PutPlan", plan: { wish: wish.id, giver: by, stage: command.stage } });
    }
    case "MarkReceived": {
      const wish = wishOf(command.wish);
      if (wish === undefined) return refused("NotFound");
      if (wish.owner !== by) return refused("NotAllowed");
      const open: GiftWish = {
        id: wish.id,
        owner: wish.owner,
        title: wish.title,
        link: wish.link,
        price: wish.price,
        note: wish.note,
        mostWanted: wish.mostWanted,
        ...(wish.occasion === undefined ? {} : { occasion: wish.occasion }),
        addedAt: wish.addedAt,
      };
      if (!command.received) return done({ _tag: "PutWish", wish: open });
      if (wish.receivedAt !== undefined) return done();
      const giver = rows.plans.find((plan) => plan.wish === wish.id)?.giver;
      return done(
        {
          _tag: "PutWish",
          wish: { ...open, receivedAt: at, ...(giver === undefined ? {} : { giftedBy: giver }) },
        },
        { _tag: "DropPlans", wish: wish.id },
      );
    }
    case "SaveLoves":
      return done({ _tag: "PutLoves", user: by, loves: command.loves });
  }
};

/** The pair's gifts as `caller` may see them: every wish, only their own plans. */
export const giftsView = (rows: GiftRows, caller: UserId): GiftsResponse => {
  const open = new Set(
    rows.wishes
      .filter((wish) => wish.owner === caller && wish.receivedAt === undefined)
      .map((wish) => wish.id),
  );
  return {
    wishes: rows.wishes.toSorted((a, b) => a.addedAt - b.addedAt),
    plans: rows.plans
      .filter((plan) => plan.giver === caller)
      .map(({ wish, stage }) => ({ wish, stage })),
    surprise: rows.plans.some((plan) => plan.giver !== caller && open.has(plan.wish)),
    loves: rows.loves.map(({ user, loves }) => ({ user, loves })),
  };
};

/** The rows `writes` leave behind: what `GiftsStore.apply` must do. */
export const applyGiftWrites = (rows: GiftRows, writes: ReadonlyArray<GiftWrite>): GiftRows =>
  writes.reduce<GiftRows>((r, write) => {
    switch (write._tag) {
      case "PutWish":
        return { ...r, wishes: [...r.wishes.filter((w) => w.id !== write.wish.id), write.wish] };
      case "DropWish":
        return { ...r, wishes: r.wishes.filter((w) => w.id !== write.id) };
      case "PutPlan":
        return {
          ...r,
          plans: [
            ...r.plans.filter((p) => !(p.wish === write.plan.wish && p.giver === write.plan.giver)),
            write.plan,
          ],
        };
      case "DropPlans":
        return {
          ...r,
          plans: r.plans.filter(
            (p) => p.wish !== write.wish || (write.giver !== undefined && p.giver !== write.giver),
          ),
        };
      case "PutLoves":
        return {
          ...r,
          loves: [
            ...r.loves.filter((l) => l.user !== write.user),
            { user: write.user, loves: write.loves },
          ],
        };
    }
  }, rows);

/** The gift tables of one room. Failures are defects, as for `RoomStore`. */
export class GiftsStore extends Context.Service<
  GiftsStore,
  {
    readonly load: Effect.Effect<GiftRows>;
    /** Applies the writes in order, as one atomic write. */
    readonly apply: (writes: ReadonlyArray<GiftWrite>) => Effect.Effect<void>;
    /** Deletes every wish, plan and "What I love": the pair is ending. */
    readonly forget: Effect.Effect<void>;
  }
>()("@billet/backend-pair-room/GiftsStore") {}

/** What a gift command answers: the caller's view after it, or why it was refused. */
export const GiftsResult = Schema.TaggedUnion({
  Done: { view: GiftsResponse },
  Refused: { reason: GiftRefusal },
});
export type GiftsResult = typeof GiftsResult.Type;

/** Runs gift commands against one room: load, decide, apply, view. */
export class GiftsRoom extends Context.Service<GiftsRoom>()("@billet/backend-pair-room/GiftsRoom", {
  make: Effect.gen(function* () {
    const store = yield* GiftsStore;
    const room = yield* RoomStore;
    // Like the room's lock: two changes at once each decide from the one before.
    const lock = yield* Semaphore.make(1);

    const run = (by: UserId, command: GiftCommand): Effect.Effect<GiftsResult> =>
      Effect.gen(function* () {
        const state = yield* room.load;
        if (state._tag !== "Active" || !state.members.some((member) => member.user === by)) {
          return GiftsResult.cases.Refused.make({ reason: "NotOpen" });
        }
        const decision = decideGift(yield* store.load, by, command, yield* Clock.currentTimeMillis);
        if (decision._tag === "Refused") {
          return GiftsResult.cases.Refused.make({ reason: decision.reason });
        }
        if (decision.writes.length > 0) yield* store.apply(decision.writes);
        return GiftsResult.cases.Done.make({ view: giftsView(yield* store.load, by) });
      }).pipe(lock.withPermits(1));

    return { run, forget: store.forget.pipe(lock.withPermits(1)) };
  }),
}) {
  static readonly layer = Layer.effect(GiftsRoom, GiftsRoom.make);
}
