import { Duration, Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { ActivityItem } from "@billet/contracts-domain/activity";
import { CatEntry } from "@billet/contracts-domain/cat";
import { RecordCatEventRequest, SaveCatRequest } from "@billet/contracts-http-api/cat";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { activityForCatEntry, activityForNote, cursorOf, itemFor } from "../src/activity.ts";
import { RoomCommand } from "../src/room-command.ts";
import { RoomService } from "../src/room-service.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import { alice, bob, catProfile, pairId, photoFrom, uuid } from "./samples.ts";

const start = 1_700_000_000_000;
const entry = (n: number, event: unknown, by = alice) =>
  Schema.decodeUnknownSync(CatEntry)({ seq: n, id: uuid(n), by, at: start + n, event });

describe("activity rows", () => {
  it("makes one item per journal entry, but none for a note's entry", () => {
    expect(activityForCatEntry(entry(1, { _tag: "Fed", grams: 40 }))).toEqual({
      id: `cat:${uuid(1)}`,
      at: start + 1,
      doer: { _tag: "Member", user: alice },
      event: { _tag: "CatFed", grams: 40 },
      target: { _tag: "Cat" },
    });
    expect(activityForCatEntry(entry(2, { _tag: "Watered" }))?.event).toEqual({
      _tag: "PlantWatered",
    });
    expect(
      activityForCatEntry(entry(3, { _tag: "NoteShared", note: "note-1", kind: "Text" })),
    ).toBeUndefined();
  });

  it("opens a photo in Moments and a text note as itself", () => {
    expect(activityForNote(photoFrom(bob)).target).toEqual({ _tag: "Moments", note: "note-1" });
    expect(activityForNote(photoFrom(bob)).event).toEqual({
      _tag: "NoteSent",
      note: "note-1",
      kind: "Photo",
    });
  });

  it("shows the doer relative to the caller, and decodes as the contract's item", () => {
    const row = activityForNote(photoFrom(bob));
    expect(itemFor(row, bob).actor).toBe("Me");
    expect(itemFor(row, alice).actor).toBe("Partner");
    expect(itemFor({ ...row, doer: { _tag: "Store" } }, alice).actor).toBe("Store");
    expect(Schema.decodeUnknownSync(ActivityItem)(itemFor(row, alice))).toEqual(
      itemFor(row, alice),
    );
  });

  it("orders cursors by time, then by id, as strings", () => {
    const early = cursorOf({ at: 9, id: Schema.decodeSync(ActivityItem.fields.id)("cat:b") });
    const later = cursorOf({ at: 10, id: Schema.decodeSync(ActivityItem.fields.id)("cat:a") });
    expect(early < later).toBe(true);
  });
});

describe("RoomService: the Inbox", () => {
  const run = <A, E>(
    store: ReturnType<typeof memoryStore>,
    program: Effect.Effect<A, E, RoomService>,
  ) =>
    Effect.runPromise(
      TestClock.setTime(start).pipe(
        Effect.andThen(program),
        Effect.provide(
          Layer.merge(
            RoomService.layer.pipe(Layer.provide(Layer.merge(store.layer, countingIds()))),
            TestClock.layer(),
          ),
        ),
      ),
    );
  const mochi = Schema.decodeSync(SaveCatRequest)({
    name: "Mochi",
    look: { model: "marmalade", coat: "natural" },
    utcOffsetSeconds: 0,
  });
  const pet = (n: number) =>
    Schema.decodeSync(RecordCatEventRequest)({ id: uuid(n), event: { _tag: "Petted" } });
  const tick = TestClock.adjust(Duration.seconds(1));
  const named = Schema.decodeSync(SaveCatRequest.fields.name);

  it("lists newest first in pages, counts unread per person, and never moves a mark back", async () => {
    const store = memoryStore();
    const result = await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* room.dispatch(RoomCommand.cases.Open.make({ pairId, members: [alice, bob] }));
          yield* room.saveCat(alice, mochi, catProfile.natureSeed);
          yield* tick;
          yield* room.recordCatEvent(bob, pet(1));
          yield* tick;
          yield* room.sendNote(bob, SendNoteRequest.cases.Text.make({ key: uuid(2), text: "hi" }));
          yield* tick;
          yield* room.recordCatEvent(alice, pet(3));

          const first = yield* room.activityPage(alice, undefined, 2);
          const second = yield* room.activityPage(alice, first.next, 2);
          const forBob = yield* room.activityPage(bob, undefined, 10);
          const newest = first.items[0];
          const readAll = yield* room.markActivityRead(
            alice,
            cursorOf({ at: newest?.at ?? 0, id: newest?.id ?? first.items[0]!.id }),
          );
          const back = yield* room.markActivityRead(alice, second.next ?? first.next!);
          return { first, second, forBob, readAll, back };
        }),
      ),
    );
    expect(result.first.items.map((i) => [i.actor, i.event._tag])).toEqual([
      ["Me", "CatPetted"],
      ["Partner", "NoteSent"],
    ]);
    expect(result.second.items.map((i) => [i.actor, i.event._tag])).toEqual([
      ["Partner", "CatPetted"],
      ["Me", "CatAdopted"],
    ]);
    expect(result.second.next).toBeUndefined();
    // The partner's note and pet are Alice's to read; her own items never are.
    expect(result.first.unread).toBe(2);
    expect(result.forBob.unread).toBe(2);
    expect(result.readAll).toBe(0);
    expect(result.back).toBe(0);
  });

  it("keeps one item for a repeated event, and forgets them all when the pair ends", async () => {
    const store = memoryStore();
    const result = await run(
      store,
      RoomService.use((room) =>
        Effect.gen(function* () {
          yield* room.dispatch(RoomCommand.cases.Open.make({ pairId, members: [alice, bob] }));
          yield* room.saveCat(alice, mochi, catProfile.natureSeed);
          yield* tick;
          yield* room.recordCatEvent(bob, pet(1));
          yield* room.recordCatEvent(bob, pet(1));
          yield* tick;
          // Two renames within a minute, as while typing: one item, with the last name.
          yield* room.saveCat(bob, { ...mochi, name: named("Mo") }, catProfile.natureSeed);
          yield* tick;
          yield* room.saveCat(bob, { ...mochi, name: named("Moti") }, catProfile.natureSeed);
          const before = yield* room.activityPage(alice, undefined, 10);
          yield* room.forgetAuthor(bob);
          const after = yield* room.activityPage(alice, undefined, 10);
          return { before, after };
        }),
      ),
    );
    expect(result.before.items.map((i) => i.event)).toEqual([
      { _tag: "CatRenamed", name: "Moti" },
      { _tag: "CatPetted" },
      { _tag: "CatAdopted", name: "Mochi" },
    ]);
    expect(result.after).toEqual({ items: [], unread: 0 });
    expect(store.memory.marks.size).toBe(0);
  });
});
