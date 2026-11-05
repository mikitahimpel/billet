import { Effect, Layer } from "effect";
import { describe, expect, it } from "vitest";
import type { UserId } from "@billet/contracts-domain/ids";
import type { SaveGiftWishRequest } from "@billet/contracts-http-api/gifts";
import {
  applyGiftWrites,
  decideGift,
  type GiftCommand,
  type GiftRows,
  GiftsRoom,
  GiftsStore,
  giftsView,
} from "../src/gifts.ts";
import { RoomStore } from "../src/room-store.ts";
import { active, alice, bob, mallory, uuid, vacant } from "./samples.ts";

const empty: GiftRows = { wishes: [], plans: [], loves: [] };

const saveWish = (n: number, title = "Bracelet"): GiftCommand => ({
  _tag: "SaveWish",
  wish: { id: uuid(n), title, link: "", price: "$65", note: "", mostWanted: false },
});

const run = (rows: GiftRows, by: UserId, command: GiftCommand, at = 1000) => {
  const decision = decideGift(rows, by, command, at);
  if (decision._tag === "Refused") throw new Error(`refused: ${decision.reason}`);
  return applyGiftWrites(rows, decision.writes);
};

const reason = (rows: GiftRows, by: UserId, command: GiftCommand) => {
  const decision = decideGift(rows, by, command, 1000);
  return decision._tag === "Refused" ? decision.reason : "Done";
};

const aliceWish = run(empty, alice, saveWish(1));

describe("gift wishes", () => {
  it("makes the wish the caller's, stamped by the room", () => {
    expect(aliceWish.wishes).toEqual([
      {
        id: uuid(1),
        owner: alice,
        title: "Bracelet",
        link: "",
        price: "$65",
        note: "",
        mostWanted: false,
        addedAt: 1000,
      },
    ]);
  });

  it("lets only the owner change or delete it", () => {
    expect(reason(aliceWish, bob, saveWish(1, "Mine now"))).toBe("NotAllowed");
    expect(reason(aliceWish, bob, { _tag: "DeleteWish", id: uuid(1) })).toBe("NotAllowed");
    const renamed = run(aliceWish, alice, saveWish(1, "Silver bracelet"), 2000);
    expect(renamed.wishes[0]).toMatchObject({ title: "Silver bracelet", addedAt: 1000 });
  });
});

describe("gift plans", () => {
  const planned = run(aliceWish, bob, { _tag: "SetPlan", wish: uuid(1), stage: "planning" });

  it("never shows the owner who plans which wish", () => {
    const owner = giftsView(planned, alice);
    expect(owner.plans).toEqual([]);
    expect(owner.surprise).toBe(true);
    expect(JSON.stringify(owner)).not.toContain(bob);

    const giver = giftsView(planned, bob);
    expect(giver.plans).toEqual([{ wish: uuid(1), stage: "planning" }]);
    expect(giver.surprise).toBe(false);
  });

  it("refuses a plan for the caller's own wish, a missing one, or one already taken", () => {
    expect(reason(aliceWish, alice, { _tag: "SetPlan", wish: uuid(1), stage: "planning" })).toBe(
      "NotAllowed",
    );
    expect(reason(aliceWish, bob, { _tag: "SetPlan", wish: uuid(9), stage: "planning" })).toBe(
      "NotFound",
    );
    expect(reason(planned, mallory, { _tag: "SetPlan", wish: uuid(1), stage: "planning" })).toBe(
      "Taken",
    );
  });

  it("moves on and lets go only the caller's own plan", () => {
    const bought = run(planned, bob, { _tag: "SetPlan", wish: uuid(1), stage: "bought" });
    expect(giftsView(bought, bob).plans).toEqual([{ wish: uuid(1), stage: "bought" }]);
    const released = run(bought, bob, { _tag: "SetPlan", wish: uuid(1) });
    expect(released.plans).toEqual([]);
    expect(giftsView(released, alice).surprise).toBe(false);
  });

  it("names the giver once the owner says it arrived, and closes the plan", () => {
    expect(reason(planned, bob, { _tag: "MarkReceived", wish: uuid(1), received: true })).toBe(
      "NotAllowed",
    );
    const received = run(
      planned,
      alice,
      { _tag: "MarkReceived", wish: uuid(1), received: true },
      5000,
    );
    expect(received.wishes[0]).toMatchObject({ receivedAt: 5000, giftedBy: bob });
    expect(received.plans).toEqual([]);
    expect(reason(received, bob, { _tag: "SetPlan", wish: uuid(1), stage: "planning" })).toBe(
      "NotAllowed",
    );

    const back = run(received, alice, { _tag: "MarkReceived", wish: uuid(1), received: false });
    expect(back.wishes[0]).not.toHaveProperty("receivedAt");
    expect(back.wishes[0]).not.toHaveProperty("giftedBy");
  });

  it("drops a deleted wish's plans with it", () => {
    const deleted = run(planned, alice, { _tag: "DeleteWish", id: uuid(1) });
    expect(deleted).toEqual({ wishes: [], plans: [], loves: [] });
  });
});

describe("GiftsRoom", () => {
  const roomWith = (state: typeof active | typeof vacant) => {
    let rows = empty;
    const gifts = Layer.succeed(GiftsStore, {
      load: Effect.sync(() => rows),
      apply: (writes) => Effect.sync(() => void (rows = applyGiftWrites(rows, writes))),
      forget: Effect.sync(() => void (rows = empty)),
    });
    const room = Layer.succeed(RoomStore, {
      load: Effect.succeed(state),
    } as unknown as RoomStore["Service"]);
    return Effect.runSync(GiftsRoom.make.pipe(Effect.provide(Layer.merge(gifts, room))));
  };

  it("answers only the room's members", () => {
    const room = roomWith(active);
    const wish: SaveGiftWishRequest = {
      id: uuid(1),
      title: "Mug",
      link: "",
      price: "",
      note: "",
      mostWanted: true,
    };
    const saved = Effect.runSync(room.run(alice, { _tag: "SaveWish", wish }));
    expect(saved._tag).toBe("Done");
    expect(Effect.runSync(room.run(mallory, { _tag: "View" }))).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });
    expect(Effect.runSync(roomWith(vacant).run(alice, { _tag: "View" }))).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });
  });
});
