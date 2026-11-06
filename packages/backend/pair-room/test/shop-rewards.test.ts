import { Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { dailyEarnCaps, EarnRef, type EarnEvent, LocalDay } from "@billet/contracts-domain/coins";
import type { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import {
  CollectionId,
  collectionOf,
  dealsOn,
  featuredSetAt,
  giftOn,
  PieceSetId,
  RoomItemId,
  roomItemOf,
  type ShopOffer,
  starterItems,
  welcomeCoins,
} from "@billet/contracts-domain/shop";
import { activityOf } from "../src/activity.ts";
import { decide } from "../src/decide.ts";
import { RoomCommand } from "../src/room-command.ts";
import type { RoomDecision } from "../src/room-decision.ts";
import { RoomService } from "../src/room-service.ts";
import { type ActiveRoom, RoomState } from "../src/room-state.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import { active, alice, bob, pairId, uuid, withCat } from "./samples.ts";

const piece = Schema.decodeSync(RoomItemId);
const setId = Schema.decodeSync(PieceSetId);
const ref = Schema.decodeSync(EarnRef);
const cozyAutumn = Schema.decodeSync(CollectionId)("cozy-autumn");
const localDay = Schema.decodeSync(LocalDay);

/** Noon UTC on 2026-11-05, a Thursday. */
const noon: EpochMillis = Date.UTC(2026, 10, 5, 12);
const today = localDay("2026-11-05");
const hour = 3_600_000;

const rich = (room: ActiveRoom = active, balance = 2_000): ActiveRoom => ({
  ...room,
  wallet: { ...room.wallet, balance },
});

const accept = (room: ActiveRoom, command: RoomCommand): RoomDecision & { _tag: "Accepted" } => {
  const decision = decide(room, command);
  if (decision._tag !== "Accepted") throw new Error(`rejected: ${decision.rejection._tag}`);
  return decision;
};

const coinsOf = (decision: RoomDecision & { _tag: "Accepted" }) =>
  decision.outputs.flatMap((output) => (output._tag === "CoinsEntered" ? [output.entry] : []));

const order = (n: number, offer: ShopOffer, by: UserId = alice, at = noon, utcOffsetSeconds = 0) =>
  RoomCommand.cases.Order.make({ id: uuid(n), by, offer, at, utcOffsetSeconds });
const item = (id: string): ShopOffer => ({ _tag: "Item", item: piece(id) });
const set = (id: string): ShopOffer => ({ _tag: "Set", set: setId(id) });

const priceOf = (id: string) => roomItemOf(id)?.price ?? Number.NaN;

/** Every piece of the collection the pair does not start with. */
const boughtFor = (collection: CollectionId) =>
  (collectionOf(collection)?.items ?? []).filter((id) => !starterItems.includes(id));

describe("the welcome coins", () => {
  const welcome = RoomCommand.cases.Welcome.make({ at: noon });

  it("are added on top of the balance, as one gift row", () => {
    const decision = accept({ ...rich(active, 30), welcomed: false }, welcome);
    expect(decision.state).toMatchObject({
      welcomed: true,
      wallet: { balance: 30 + welcomeCoins },
    });
    expect(coinsOf(decision)).toEqual([
      { id: "gift:welcome", kind: "gift", amount: welcomeCoins, ref: "welcome", at: noon },
    ]);
  });

  it("are given once", () => {
    const once = accept({ ...active, welcomed: false }, welcome).state;
    expect(accept(once, welcome)).toEqual({ _tag: "Accepted", state: once, outputs: [] });
  });

  it("are owed by a room stored before them, which reads with no bonuses and no list earns", () => {
    const stored = Schema.decodeUnknownSync(RoomState)({
      _tag: "Active",
      pairId,
      members: active.members,
      lastSeq: 0,
      streakDays: 0,
      inks: [],
      items: [],
      wishlist: [],
      wallet: { balance: 30, care: 0, notes: 0, games: 0 },
    });
    expect(stored).toMatchObject({
      welcomed: false,
      bonuses: [],
      wallet: { balance: 30, lists: 0 },
    });
  });
});

describe("a daily deal", () => {
  it("is charged at its deal price on the pair's local day", () => {
    const [deal] = dealsOn(pairId, today);
    if (deal === undefined) throw new Error("no deal");
    const decision = accept(rich(), order(1, item(deal.item)));
    expect(deal.price).toBeLessThan(priceOf(deal.item));
    expect(coinsOf(decision).map((entry) => entry.amount)).toEqual([-deal.price]);
    expect(decision.outputs).toContainEqual(
      expect.objectContaining({ _tag: "Purchased", offer: `deal:${today}`, coins: deal.price }),
    );
  });

  it("follows the day: the day after, a piece no longer a deal costs its catalog price", () => {
    const tomorrow = localDay("2026-11-06");
    const ended = dealsOn(pairId, today).find(
      (deal) => !dealsOn(pairId, tomorrow).some((next) => next.item === deal.item),
    );
    if (ended === undefined) throw new Error("the same deals two days running");
    const after = accept(rich(), order(1, item(ended.item), alice, noon + 24 * hour));
    expect(coinsOf(after).map((entry) => entry.amount)).toEqual([-priceOf(ended.item)]);
    // 23:00 UTC is already the 6th two hours east, so the caller's clock moves the deal too.
    const east = accept(rich(), order(2, item(ended.item), alice, noon + 11 * hour, 7_200));
    expect(coinsOf(east).map((entry) => entry.amount)).toEqual([-priceOf(ended.item)]);
  });

  it("counts the day on the cat's clock when the order names none", () => {
    const [deal] = dealsOn(pairId, localDay("2026-11-06"));
    if (deal === undefined) throw new Error("no deal");
    const east: ActiveRoom = rich({
      ...withCat,
      cat: { ...withCat.cat!, profile: { ...withCat.cat!.profile, utcOffsetSeconds: 7_200 } },
    });
    const command = RoomCommand.cases.Order.make({
      id: uuid(1),
      by: alice,
      offer: item(deal.item),
      at: noon + 11 * hour,
    });
    expect(coinsOf(accept(east, command)).map((entry) => entry.amount)).toEqual([-deal.price]);
  });
});

describe("a treat", () => {
  it("needs a cat", () => {
    expect(decide(rich(), order(1, { _tag: "Treat" }))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "CatNotAdopted" },
    });
  });

  it("costs 10, feeds the cat under the order's id, earns nothing, and can be bought again", () => {
    const first = accept(rich(withCat, 25), order(1, { _tag: "Treat" }));
    expect(coinsOf(first)).toEqual([
      { id: `spend:${uuid(1)}`, kind: "spend", amount: -10, ref: "treat", at: noon },
    ]);
    expect(first.outputs).toContainEqual({
      _tag: "CatEntryAppended",
      entry: { seq: 1, id: uuid(1), by: alice, at: noon, event: { _tag: "Fed", grams: 20 } },
    });
    expect(first.state.items).toEqual([]);
    expect(first.state.wallet).toMatchObject({ balance: 15, care: 0 });
    const second = accept(first.state, order(2, { _tag: "Treat" }));
    expect(second.state.wallet.balance).toBe(5);
    expect(second.state.cat?.lastSeq).toBe(2);
    expect(decide(second.state, order(3, { _tag: "Treat" }))).toMatchObject({
      _tag: "Rejected",
      rejection: { _tag: "NotEnoughCoins", needed: 10, have: 5 },
    });
  });
});

describe("the daily gift", () => {
  const open = (by: UserId = alice, at = noon, utcOffsetSeconds = 0) =>
    RoomCommand.cases.OpenGift.make({ by, at, utcOffsetSeconds });
  const owned = new Set<string>(starterItems);

  it("opens once a day for the pair, and again after the pair's midnight", () => {
    const first = accept(active, open());
    const reward = giftOn(pairId, today, owned);
    expect(first.state.giftDay).toBe(today);
    expect(coinsOf(first)).toEqual([
      reward._tag === "Coins"
        ? { id: `gift:${today}`, kind: "gift", amount: reward.coins, ref: today, at: noon }
        : { id: `gift:${today}`, kind: "gift", amount: 0, ref: reward.item, at: noon },
    ]);
    expect(decide(first.state, open(bob))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "GiftTaken", day: today },
    });
    // 23:00 UTC is the next day two hours east.
    const tomorrow = accept(first.state, open(bob, noon + 11 * hour, 7_200));
    expect(tomorrow.state.giftDay).toBe("2026-11-06");
  });

  it("gives a piece with an amount-0 entry that names it, or coins once the pair has it", () => {
    // On this day the pair-1 gift is the yarn ball (see contracts-fixtures/shop-offers.json).
    const day = localDay("2025-02-28");
    expect(giftOn(pairId, day, owned)).toEqual({ _tag: "Item", item: "yarn" });
    const at = Date.UTC(2025, 1, 28, 9);
    const decision = accept(active, open(alice, at));
    expect(coinsOf(decision)).toEqual([
      { id: `gift:${day}`, kind: "gift", amount: 0, ref: "yarn", at },
    ]);
    expect(decision.state.items).toEqual(["yarn"]);
    const owner = accept({ ...active, items: [piece("yarn")] }, open(alice, at));
    expect(coinsOf(owner)[0]?.amount).toBeGreaterThan(0);
  });
});

describe("a collection bonus", () => {
  const claim = (by: UserId = alice) =>
    RoomCommand.cases.ClaimBonus.make({ by, at: noon, collection: cozyAutumn });

  it("is refused while a piece is missing", () => {
    expect(decide({ ...active, items: boughtFor(cozyAutumn).slice(1) }, claim())).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "CollectionIncomplete", collection: cozyAutumn },
    });
  });

  it("pays once, when every piece is owned, the starters counted", () => {
    const decision = accept({ ...active, items: boughtFor(cozyAutumn) }, claim());
    expect(coinsOf(decision)).toEqual([
      { id: "bonus:cozy-autumn", kind: "bonus", amount: 150, ref: "cozy-autumn", at: noon },
    ]);
    expect(decision.state.bonuses).toEqual([cozyAutumn]);
    expect(decide(decision.state, claim(bob))).toEqual({
      _tag: "Rejected",
      rejection: { _tag: "BonusTaken", collection: cozyAutumn },
    });
  });
});

describe("earning in the app", () => {
  const earn = (event: EarnEvent, at = noon, utcOffsetSeconds = 0) =>
    RoomCommand.cases.Earn.make({ by: alice, at, utcOffsetSeconds, event });
  const tick = (n: number) => earn({ _tag: "ListTicked", item: ref(`item-${n}`) });

  it("pays each kind its reward under an entry per ref", () => {
    const cases: ReadonlyArray<readonly [EarnEvent, string, number]> = [
      [{ _tag: "WishReceived", wish: ref("w1") }, "earn:wish:w1", 20],
      [{ _tag: "DateMatched", idea: ref("i1") }, "earn:date:i1", 10],
      [{ _tag: "GuessHit", round: today, question: 7 }, "earn:guess:2026-11-05.7", 2],
      [{ _tag: "RoundPlayed", round: today }, "earn:round:2026-11-05", 10],
      [{ _tag: "DateRated", plan: ref("p1") }, "earn:plan:p1", 30],
      [{ _tag: "ListTicked", item: ref("l1") }, "earn:list:l1", 5],
      [{ _tag: "MomentAdded", moment: ref("m1") }, "earn:moment:m1", 10],
      [{ _tag: "NoteAdded", note: ref("n1") }, "earn:note:n1", 5],
    ];
    for (const [event, id, amount] of cases) {
      expect(coinsOf(accept(active, earn(event)))).toEqual([
        { id, kind: "earn", amount, ref: id.split(":")[2], at: noon },
      ]);
    }
  });

  it("stops ticked items at the day's cap, and starts again at the local midnight", () => {
    const full = [1, 2, 3].reduce((room, n) => accept(room, tick(n)).state, active);
    expect(full.wallet).toMatchObject({ balance: 15, lists: dailyEarnCaps.lists });
    expect(coinsOf(accept(full, tick(4)))).toEqual([]);
    // 23:00 UTC is already the 6th two hours east.
    const late = accept(
      full,
      earn({ _tag: "ListTicked", item: ref("item-5") }, noon + 11 * hour, 7_200),
    );
    expect(coinsOf(late).map((entry) => entry.amount)).toEqual([5]);
    expect(late.state.wallet).toMatchObject({ day: "2026-11-06", lists: 5 });
  });

  it("counts moments and notes against the cap the room's own notes fill", () => {
    const nearly: ActiveRoom = {
      ...active,
      wallet: { ...active.wallet, day: today, notes: dailyEarnCaps.notes - 5 },
    };
    const moment = accept(nearly, earn({ _tag: "MomentAdded", moment: ref("m1") }));
    expect(coinsOf(moment).map((entry) => entry.amount)).toEqual([5]);
    expect(coinsOf(accept(moment.state, earn({ _tag: "NoteAdded", note: ref("n1") })))).toEqual([]);
  });
});

const run = <A>(
  store: ReturnType<typeof memoryStore>,
  program: Effect.Effect<A, never, RoomService>,
) =>
  Effect.runPromise(
    TestClock.setTime(noon).pipe(
      Effect.andThen(program),
      Effect.provide(
        Layer.merge(
          RoomService.layer.pipe(Layer.provide(Layer.merge(store.layer, countingIds()))),
          TestClock.layer(),
        ),
      ),
    ),
  );

const balanceOf = (store: ReturnType<typeof memoryStore>) =>
  store.memory.state._tag === "Active" ? store.memory.state.wallet.balance : Number.NaN;

describe("RoomService: coins", () => {
  it("writes the welcome coins once when a room opens, however often it is opened", async () => {
    const store = memoryStore();
    await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* room.dispatch(RoomCommand.cases.Open.make({ pairId, members: [alice, bob] }));
          yield* room.dispatch(RoomCommand.cases.Open.make({ pairId, members: [bob, alice] }));
        }),
      ),
    );
    expect(balanceOf(store)).toBe(welcomeCoins);
    expect(store.memory.coins.map((entry) => entry.id)).toEqual(["gift:welcome"]);
  });

  it("gives a room opened before the welcome coins them once, on its next read or command", async () => {
    const store = memoryStore();
    store.memory.state = { ...rich(active, 30), welcomed: false };
    await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* room.settled;
          yield* room.dispatch(
            RoomCommand.cases.SetPresence.make({ user: alice, state: "drawing" }),
          );
          yield* room.settled;
        }),
      ),
    );
    expect(balanceOf(store)).toBe(30 + welcomeCoins);
    expect(store.memory.coins.filter((entry) => entry.id === "gift:welcome")).toHaveLength(1);
  });

  it("charges an order submitted twice at once once, and answers the second with the first", async () => {
    const store = memoryStore();
    store.memory.state = rich();
    const [first, second] = await run(
      store,
      RoomService.use((room) =>
        Effect.all(
          [room.order(alice, uuid(1), item("tower")), room.order(alice, uuid(1), item("tower"))],
          { concurrency: "unbounded" },
        ),
      ),
    );
    expect(first).toMatchObject({ _tag: "Accepted" });
    expect(second).toMatchObject({
      _tag: "Accepted",
      outputs: [{ _tag: "CoinsRepeated", entry: { id: `spend:${uuid(1)}`, amount: -540 } }],
    });
    expect(balanceOf(store)).toBe(2_000 - 540);
    expect(store.memory.coins).toHaveLength(1);
  });

  it("lets one of the partners' orders at once through when only one is affordable", async () => {
    const store = memoryStore();
    store.memory.state = rich(active, 600);
    const decisions = await run(
      store,
      RoomService.use((room) =>
        Effect.all(
          [room.order(alice, uuid(1), item("tower")), room.order(bob, uuid(2), item("armchair"))],
          { concurrency: "unbounded" },
        ),
      ),
    );
    expect(decisions.map((decision) => decision._tag).toSorted()).toEqual(["Accepted", "Rejected"]);
    expect(store.memory.coins).toHaveLength(1);
    expect(balanceOf(store)).toBe(600 + (store.memory.coins[0]?.amount ?? Number.NaN));
    expect(balanceOf(store)).toBeGreaterThanOrEqual(0);
  });

  it("opens the day's gift once for both partners", async () => {
    const store = memoryStore();
    store.memory.state = active;
    const [mine, theirs] = await run(
      store,
      RoomService.use((room) =>
        Effect.all([room.openGift(alice, undefined), room.openGift(bob, undefined)], {
          concurrency: "unbounded",
        }),
      ),
    );
    expect(mine).toMatchObject({ _tag: "Accepted" });
    expect(theirs).toMatchObject({
      _tag: "Accepted",
      outputs: [{ _tag: "CoinsRepeated", entry: { id: `gift:${today}` } }],
    });
    expect(store.memory.coins.map((entry) => entry.id)).toEqual([`gift:${today}`]);
  });

  it("counts the gift's day on the cat's clock when the caller names none", async () => {
    const store = memoryStore();
    // 23:00 UTC is the 6th on a cat's clock two hours east.
    store.memory.state = {
      ...withCat,
      cat: { ...withCat.cat!, profile: { ...withCat.cat!.profile, utcOffsetSeconds: 7_200 } },
    };
    await run(
      store,
      TestClock.setTime(noon + 11 * hour).pipe(
        Effect.andThen(RoomService.use((room) => room.openGift(alice, undefined))),
      ),
    );
    expect(store.memory.coins.map((entry) => entry.id)).toEqual(["gift:2026-11-06"]);
  });

  it("pays a collection's bonus once, to both partners asking at once", async () => {
    const store = memoryStore();
    store.memory.state = { ...active, items: boughtFor(cozyAutumn) };
    const [first, again] = await run(
      store,
      RoomService.use((room) =>
        Effect.all([room.claimBonus(alice, cozyAutumn), room.claimBonus(bob, cozyAutumn)], {
          concurrency: "unbounded",
        }),
      ),
    );
    expect(first).toMatchObject({ _tag: "Accepted" });
    expect(again).toMatchObject({ outputs: [{ _tag: "CoinsRepeated" }] });
    expect(balanceOf(store)).toBe(150);
  });

  it("pays an app earn once per ref", async () => {
    const store = memoryStore();
    store.memory.state = active;
    const wish: EarnEvent = { _tag: "WishReceived", wish: ref("w1") };
    const [, again] = await run(
      store,
      RoomService.use((room) =>
        Effect.all([room.earn(alice, wish, undefined), room.earn(bob, wish, undefined)], {
          concurrency: "unbounded",
        }),
      ),
    );
    expect(again).toMatchObject({ outputs: [{ _tag: "CoinsRepeated" }] });
    expect(balanceOf(store)).toBe(20);
  });
});

describe("the Inbox rows of coins", () => {
  it("writes a purchase, an opened gift and a bonus in the decision that moves the coins", () => {
    const bought = accept(rich(), order(1, set("window-glow")));
    const giftAt = Date.UTC(2025, 1, 28, 9);
    const gift = accept(
      active,
      RoomCommand.cases.OpenGift.make({ by: bob, at: giftAt, utcOffsetSeconds: 0 }),
    );
    const bonus = accept(
      { ...active, items: boughtFor(cozyAutumn) },
      RoomCommand.cases.ClaimBonus.make({ by: alice, at: noon, collection: cozyAutumn }),
    );
    expect(activityOf(bought.outputs, noon)).toEqual([
      {
        id: `spend:${uuid(1)}`,
        at: noon,
        doer: { _tag: "Member", user: alice },
        event: {
          _tag: "Purchased",
          offer: "bundle:window-glow",
          items: ["lantern", "monstera", "print"],
          coins: 270,
        },
        target: { _tag: "ShopOffer", id: "bundle:window-glow" },
      },
    ]);
    expect(activityOf(gift.outputs, noon)).toEqual([
      {
        id: "gift:2025-02-28",
        at: giftAt,
        doer: { _tag: "Member", user: bob },
        event: { _tag: "GiftClaimed", coins: 0 },
        target: { _tag: "ShopItem", id: "yarn" },
      },
    ]);
    expect(activityOf(bonus.outputs, noon)).toEqual([
      {
        id: "bonus:cozy-autumn",
        at: noon,
        doer: { _tag: "Member", user: alice },
        event: { _tag: "BonusEarned", collection: "cozy-autumn", coins: 150 },
      },
    ]);
  });

  it("names a featured set, a piece and a treat", () => {
    const featured = featuredSetAt(noon);
    const decision = accept(rich(), order(1, set(featured.id)));
    expect(activityOf(decision.outputs, noon)[0]).toMatchObject({
      event: { _tag: "Purchased", offer: `featured:${featured.id}` },
      target: { _tag: "ShopOffer", id: `featured:${featured.id}` },
    });
    const tower = accept(rich(), order(2, item("tower")));
    expect(activityOf(tower.outputs, noon)).toEqual([
      {
        id: `spend:${uuid(2)}`,
        at: noon,
        doer: { _tag: "Member", user: alice },
        event: { _tag: "Purchased", items: ["tower"], coins: 540 },
        target: { _tag: "ShopItem", id: "tower" },
      },
    ]);
    const treat = accept(rich(withCat), order(3, { _tag: "Treat" }));
    expect(activityOf(treat.outputs, noon).map((row) => row.event)).toEqual([
      { _tag: "CatFed", grams: 20 },
      { _tag: "Purchased", items: ["treat"], coins: 10 },
    ]);
  });

  it("writes no row for an earn or the welcome coins", () => {
    const earned = accept(
      active,
      RoomCommand.cases.Earn.make({
        by: alice,
        at: noon,
        utcOffsetSeconds: 0,
        event: { _tag: "WishReceived", wish: ref("w1") },
      }),
    );
    expect(activityOf(earned.outputs, noon)).toEqual([]);
    const welcomed = accept(
      { ...active, welcomed: false },
      RoomCommand.cases.Welcome.make({ at: noon }),
    );
    expect(activityOf(welcomed.outputs, noon)).toEqual([]);
  });
});
