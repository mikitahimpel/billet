import { Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { dailyEarnCaps, LocalDay } from "@billet/contracts-domain/coins";
import type { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import {
  type ListCommand,
  ListId,
  ListItemId,
  type ListKind,
  type SharedList,
} from "@billet/contracts-domain/list";
import { activityOf } from "../src/activity.ts";
import { decide } from "../src/decide.ts";
import { changeList } from "../src/lists.ts";
import { RoomCommand } from "../src/room-command.ts";
import type { RoomDecision } from "../src/room-decision.ts";
import { RoomService } from "../src/room-service.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import { active, alice, bob, mallory, uuid } from "./samples.ts";

const listId = (n: number) => Schema.decodeSync(ListId)(uuid(1000 + n));
const itemId = (n: number) => Schema.decodeSync(ListItemId)(uuid(2000 + n));

/** Noon UTC on 2026-11-05. */
const noon: EpochMillis = Date.UTC(2026, 10, 5, 12);
const minute = 60_000;

let keys = 0;
const key = (): IdempotencyKey => uuid(5000 + (keys += 1));

const create = (kind: ListKind = "watch", list = listId(1)): ListCommand => ({
  _tag: "CreateList",
  key: key(),
  list,
  kind,
  title: kind === "groceries" ? "Groceries" : "To watch",
  icon: { symbol: "popcorn.fill", tint: "coral" },
});
const add = (n: number, text = `Item ${n}`, list = listId(1)): ListCommand => ({
  _tag: "AddItem",
  key: key(),
  list,
  item: itemId(n),
  text,
});
const tick = (n: number, list = listId(1)): ListCommand => ({
  _tag: "TickItem",
  key: key(),
  list,
  item: itemId(n),
});

const empty = (kind: ListKind = "watch"): SharedList => ({
  id: listId(1),
  kind,
  title: "To watch",
  icon: { symbol: "popcorn.fill", tint: "coral" },
  items: [],
});

/** The list after each change, as `changeList` saves it. */
const after = (changes: ReadonlyArray<readonly [UserId, ListCommand]>, start?: SharedList) =>
  changes.reduce<SharedList | undefined>((list, [by, change], i) => {
    const outcome = changeList(list, by, noon + i * minute, change);
    switch (outcome._tag) {
      case "Saved":
        return outcome.list;
      case "Deleted":
        return undefined;
      case "Unchanged":
        return list;
      case "Refused":
        throw new Error(outcome.rejection._tag);
    }
  }, start);

describe("changeList", () => {
  it("makes a list once: a second create under its id changes nothing", () => {
    const made = after([[alice, create()]]);
    expect(made).toEqual(empty());
    expect(changeList(made, bob, noon, create())).toEqual({ _tag: "Unchanged" });
  });

  it("renames a list, and refuses a list that is gone", () => {
    const rename: ListCommand = {
      _tag: "RenameList",
      key: key(),
      list: listId(1),
      title: "Films",
      icon: { symbol: "film.fill", tint: "sky" },
    };
    expect(after([[bob, rename]], empty())).toMatchObject({
      title: "Films",
      icon: { symbol: "film.fill", tint: "sky" },
    });
    expect(changeList(undefined, bob, noon, rename)).toMatchObject({
      _tag: "Refused",
      rejection: { _tag: "ListNotFound" },
    });
  });

  it("deletes a list for both, and a second delete changes nothing", () => {
    const remove: ListCommand = { _tag: "DeleteList", key: key(), list: listId(1) };
    expect(changeList(empty(), alice, noon, remove)).toEqual({ _tag: "Deleted", list: listId(1) });
    expect(changeList(undefined, bob, noon, remove)).toEqual({ _tag: "Unchanged" });
  });

  it("adds items oldest first with their author and time, each id once", () => {
    const list = after(
      [
        [alice, add(1, "Past Lives")],
        [bob, add(2, "Dune")],
        [bob, add(1, "Past Lives")],
      ],
      empty(),
    );
    expect(list?.items).toEqual([
      { id: itemId(1), text: "Past Lives", author: alice, addedAt: noon, wants: [] },
      { id: itemId(2), text: "Dune", author: bob, addedAt: noon + minute, wants: [] },
    ]);
  });

  it("keeps the fields the later lists need", () => {
    const list = after(
      [
        [
          alice,
          {
            _tag: "AddItem",
            key: key(),
            list: listId(1),
            item: itemId(1),
            text: "Oat milk",
            quantity: "2",
            note: "barista",
            icon: "milk",
            aisle: "dairy",
          },
        ],
        [
          bob,
          {
            _tag: "EditItem",
            key: key(),
            list: listId(1),
            item: itemId(1),
            text: "Lisbon",
            media: { kind: "movie", tmdb: 666277 },
            country: "PT",
            place: true,
            visitedIn: "2026-10",
            moments: ["00000000-0000-4000-8000-0000000000d1"],
          },
        ],
      ],
      empty(),
    );
    // An edit sets every detail: the ones it leaves out are cleared, the author and time stay.
    expect(list?.items).toEqual([
      {
        id: itemId(1),
        text: "Lisbon",
        author: alice,
        addedAt: noon,
        media: { kind: "movie", tmdb: 666277 },
        country: "PT",
        place: true,
        visitedIn: "2026-10",
        moments: ["00000000-0000-4000-8000-0000000000d1"],
        wants: [],
      },
    ]);
  });

  it("lets the first tick win, and an untick open it again", () => {
    const ticked = after(
      [
        [alice, add(1)],
        [bob, tick(1)],
      ],
      empty(),
    );
    expect(ticked?.items[0]).toMatchObject({ doneBy: bob, doneAt: noon + minute });
    expect(changeList(ticked, alice, noon + 5 * minute, tick(1))).toEqual({ _tag: "Unchanged" });

    const reopened = after(
      [[alice, { _tag: "UntickItem", key: key(), list: listId(1), item: itemId(1) }]],
      ticked,
    );
    expect(reopened?.items[0]).toEqual({
      id: itemId(1),
      text: "Item 1",
      author: alice,
      addedAt: noon,
      wants: [],
    });
  });

  it("deletes an item, and deleting one that is gone changes nothing", () => {
    const list = after(
      [
        [alice, add(1)],
        [alice, add(2)],
      ],
      empty(),
    );
    const remove: ListCommand = {
      _tag: "DeleteItem",
      key: key(),
      list: listId(1),
      item: itemId(1),
    };
    expect(after([[bob, remove]], list)?.items.map((item) => item.id)).toEqual([itemId(2)]);
    expect(changeList(after([[bob, remove]], list), bob, noon, remove)).toEqual({
      _tag: "Unchanged",
    });
    expect(changeList(undefined, bob, noon, remove)).toEqual({ _tag: "Unchanged" });
  });

  it("keeps who wants an item, in the order they said so", () => {
    const want = (wants: boolean): ListCommand => ({
      _tag: "WantItem",
      key: key(),
      list: listId(1),
      item: itemId(1),
      wants,
    });
    const list = after(
      [
        [alice, add(1)],
        [bob, want(true)],
        [alice, want(true)],
      ],
      empty(),
    );
    expect(list?.items[0]?.wants).toEqual([bob, alice]);
    expect(after([[bob, want(false)]], list)?.items[0]?.wants).toEqual([alice]);
  });

  it("refuses a change to an item its list no longer has", () => {
    expect(changeList(empty(), alice, noon, tick(9))).toMatchObject({
      _tag: "Refused",
      rejection: { _tag: "ListItemNotFound" },
    });
    expect(changeList(undefined, alice, noon, add(1))).toMatchObject({
      _tag: "Refused",
      rejection: { _tag: "ListNotFound" },
    });
  });
});

const accept = (room: ActiveRoom, command: RoomCommand) => {
  const decision = decide(room, command);
  if (decision._tag !== "Accepted") throw new Error(`rejected: ${decision.rejection._tag}`);
  return decision;
};

const changeOf = (
  change: ListCommand,
  list: SharedList | undefined,
  options: { by?: UserId; at?: EpochMillis; paid?: boolean } = {},
) =>
  RoomCommand.cases.ChangeList.make({
    by: options.by ?? alice,
    at: options.at ?? noon,
    utcOffsetSeconds: 0,
    change,
    ...(list === undefined ? {} : { list }),
    paid: options.paid ?? false,
  });

const coinsOf = (decision: RoomDecision & { _tag: "Accepted" }) =>
  decision.outputs.flatMap((output) => (output._tag === "CoinsEntered" ? [output.entry] : []));

describe("decide: lists", () => {
  it("refuses a stranger", () => {
    expect(decide(active, changeOf(create(), undefined, { by: mallory }))).toMatchObject({
      _tag: "Rejected",
      rejection: { _tag: "NotAMember", user: mallory },
    });
  });

  it("pays a tick of a we-want-to item in the same decision, under the item", () => {
    const list = after([[alice, add(1)]], empty());
    const decision = accept(active, changeOf(tick(1), list, { by: bob }));
    expect(coinsOf(decision)).toEqual([
      { id: `earn:list:${itemId(1)}`, kind: "earn", amount: 5, ref: itemId(1), at: noon },
    ]);
    expect(decision.state.wallet).toMatchObject({ balance: 5, lists: 5 });
    expect(decision.outputs.map((output) => output._tag)).toEqual(["ListSaved", "CoinsEntered"]);
  });

  it("pays nothing for groceries, for an item paid before, or past the day's cap", () => {
    const groceries = after([[alice, add(1)]], empty("groceries"));
    expect(coinsOf(accept(active, changeOf(tick(1), groceries)))).toEqual([]);

    const watch = after([[alice, add(1)]], empty());
    expect(coinsOf(accept(active, changeOf(tick(1), watch, { paid: true })))).toEqual([]);

    const capped: ActiveRoom = {
      ...active,
      wallet: {
        ...active.wallet,
        day: Schema.decodeSync(LocalDay)("2026-11-05"),
        lists: dailyEarnCaps.lists,
      },
    };
    expect(coinsOf(accept(capped, changeOf(tick(1), watch)))).toEqual([]);
  });

  it("pays nothing when the partner ticked first", () => {
    const ticked = after(
      [
        [alice, add(1)],
        [bob, tick(1)],
      ],
      empty(),
    );
    const decision = accept(active, changeOf(tick(1), ticked));
    expect(decision.outputs).toEqual([]);
  });

  it("counts a partner's adds to one list within ten minutes as one Inbox item", () => {
    const adds = [add(1, "Milk"), add(2, "Pears"), add(3, "Bread")];
    let list: SharedList | undefined = empty("groceries");
    const rows = adds.flatMap((change, i) => {
      const at = noon + i * 3 * minute;
      const decision = accept(active, changeOf(change, list, { by: bob, at }));
      list = after([[bob, change]], list);
      return activityOf(decision.outputs, at);
    });
    expect(new Set(rows.map((row) => row.id)).size).toBe(1);
    expect(rows.at(-1)).toMatchObject({
      at: noon + 6 * minute,
      doer: { _tag: "Member", user: bob },
      event: { _tag: "ListItemAdded", kind: "groceries", count: 3, text: "Bread" },
      target: { _tag: "List", list: listId(1) },
    });

    // The next window, or the other partner, is a new item.
    const later = accept(active, changeOf(add(4), list, { by: bob, at: noon + 11 * minute }));
    const theirs = accept(active, changeOf(add(5), list, { by: alice, at: noon + 7 * minute }));
    const [laterRow] = activityOf(later.outputs, noon);
    const [theirRow] = activityOf(theirs.outputs, noon);
    expect(laterRow?.id).not.toBe(rows[0]?.id);
    expect(theirRow?.id).not.toBe(rows[0]?.id);
    expect(laterRow?.event).toMatchObject({ count: 1 });
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

const opened = () => {
  const store = memoryStore();
  store.memory.state = { ...active, welcomed: true };
  return store;
};

describe("RoomService: lists", () => {
  it("stores the lists both partners change, and refuses before the room opens", async () => {
    const store = memoryStore();
    const refused = await run(
      store,
      RoomService.use((room) => room.changeList(alice, create(), undefined)),
    );
    expect(refused).toMatchObject({ _tag: "Rejected", rejection: { _tag: "RoomNotOpen" } });

    const room = opened();
    await run(
      room,
      RoomService.use((service) =>
        Effect.gen(function* () {
          yield* service.changeList(alice, create(), undefined);
          yield* service.changeList(bob, add(1, "Dune"), undefined);
          yield* service.changeList(alice, create("groceries", listId(2)), undefined);
        }),
      ),
    );
    expect(room.memory.lists.map((list) => [list.id, list.items.length])).toEqual([
      [listId(1), 1],
      [listId(2), 0],
    ]);
  });

  it("applies a key once: a retried change after a later one changes nothing", async () => {
    const store = opened();
    const first = add(1, "Dune");
    const untick: ListCommand = {
      _tag: "UntickItem",
      key: key(),
      list: listId(1),
      item: itemId(1),
    };
    const ticked = tick(1);
    await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* room.changeList(alice, create(), undefined);
          yield* room.changeList(alice, first, undefined);
          yield* room.changeList(bob, ticked, undefined);
          yield* room.changeList(alice, untick, undefined);
          const again = yield* room.changeList(bob, ticked, undefined);
          expect(again).toMatchObject({ _tag: "Accepted", outputs: [] });
        }),
      ),
    );
    expect(store.memory.lists[0]?.items[0]?.doneAt).toBeUndefined();
  });

  it("pays a tick once, however often the item is ticked again", async () => {
    const store = opened();
    await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* room.changeList(alice, create(), undefined);
          yield* room.changeList(alice, add(1), undefined);
          yield* room.changeList(bob, tick(1), undefined);
          yield* room.changeList(
            bob,
            { _tag: "UntickItem", key: key(), list: listId(1), item: itemId(1) },
            undefined,
          );
          yield* room.changeList(alice, tick(1), undefined);
        }),
      ),
    );
    expect(store.memory.coins.map((entry) => entry.id)).toEqual([`earn:list:${itemId(1)}`]);
    expect(store.memory.lists[0]?.items[0]?.doneBy).toBe(alice);
  });

  it("deletes a list with its items for both", async () => {
    const store = opened();
    const lists = await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* room.changeList(alice, create(), undefined);
          yield* room.changeList(alice, add(1), undefined);
          yield* room.changeList(
            bob,
            { _tag: "DeleteList", key: key(), list: listId(1) },
            undefined,
          );
          const refused = yield* room.changeList(alice, add(2), undefined);
          expect(refused).toMatchObject({ rejection: { _tag: "ListNotFound" } });
          return yield* room.lists;
        }),
      ),
    );
    expect(lists).toEqual([]);
  });

  it("forgets every list when the pair ends", async () => {
    const store = opened();
    await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* room.changeList(alice, create(), undefined);
          yield* room.forgetLists;
        }),
      ),
    );
    expect(store.memory.lists).toEqual([]);
    expect(store.memory.listKeys.size).toBe(0);
  });
});
