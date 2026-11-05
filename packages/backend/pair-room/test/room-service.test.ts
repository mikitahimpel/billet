import { Clock, Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { IdempotencyKey } from "@billet/contracts-domain/ids";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { RoomCommand } from "../src/room-command.ts";
import { RoomService } from "../src/room-service.ts";
import type { RoomStore } from "../src/room-store.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import { active, alice, bob, image, mallory, pairId, vacant } from "./samples.ts";

const runWith = <A, E>(
  store: Layer.Layer<RoomStore>,
  program: Effect.Effect<A, E, RoomService>,
): Promise<A> =>
  Effect.runPromise(
    program.pipe(
      Effect.provide(RoomService.layer.pipe(Layer.provide(Layer.merge(store, countingIds())))),
    ),
  );

const open = RoomCommand.cases.Open.make({ pairId, members: [alice, bob] });
let keyCount = 0;
/** A new key each time, so repeated sends are different notes unless a test reuses a key. */
const newKey = () =>
  Schema.decodeSync(IdempotencyKey)(
    `00000000-0000-4000-8000-${String((keyCount += 1)).padStart(12, "0")}`,
  );
const photo = () =>
  SendNoteRequest.cases.Photo.make({
    key: newKey(),
    image,
    width: 4032,
    height: 3024,
    preview: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
  });

describe("RoomService", () => {
  it("opens a room and commits its state", async () => {
    const { memory, layer } = memoryStore();
    await runWith(
      layer,
      RoomService.use((room) => room.dispatch(open)),
    );
    expect(memory.state).toEqual(active);
  });

  it("stamps a note with server id, author and time, and stores it", async () => {
    const { memory, layer } = memoryStore();
    const decision = await runWith(
      layer,
      Effect.gen(function* () {
        const room = yield* RoomService;
        yield* room.dispatch(open);
        yield* TestClock.setTime(1_700_000_000_000);
        return yield* room.sendNote(alice, photo());
      }).pipe(Effect.provide(TestClock.layer())),
    );
    const note = {
      _tag: "Photo",
      id: "note-1",
      author: alice,
      sentAt: 1_700_000_000_000,
      image,
      width: 4032,
      height: 3024,
      preview: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
    };
    expect(decision).toMatchObject({ _tag: "Accepted", state: { lastSeq: 1 } });
    expect(memory.notes).toEqual([{ seq: 1, note }]);
  });

  it("keeps a drawing's strokes when stamping it", async () => {
    const { memory, layer } = memoryStore();
    const compact = { version: 1, strokes: [] } as const;
    await runWith(
      layer,
      Effect.gen(function* () {
        const room = yield* RoomService;
        yield* room.dispatch(open);
        yield* room.sendNote(
          bob,
          SendNoteRequest.cases.Drawing.make({ key: newKey(), compact, image }),
        );
      }),
    );
    expect(memory.notes[0]?.note).toMatchObject({ _tag: "Drawing", compact, author: bob });
  });

  it("writes nothing for a rejected command", async () => {
    const { memory, layer } = memoryStore();
    const decision = await runWith(
      layer,
      Effect.gen(function* () {
        const room = yield* RoomService;
        yield* room.dispatch(open);
        return yield* room.sendNote(mallory, photo());
      }),
    );
    expect(decision).toMatchObject({ _tag: "Rejected", rejection: { _tag: "NotAMember" } });
    expect(memory.state).toEqual(active);
    expect(memory.notes).toEqual([]);
  });

  it("gives concurrent notes a gapless order, even though load yields", async () => {
    const { memory, layer } = memoryStore();
    await runWith(
      layer,
      Effect.gen(function* () {
        const room = yield* RoomService;
        yield* room.dispatch(open);
        yield* Effect.all(
          Array.from({ length: 25 }, () => room.sendNote(alice, photo())),
          { concurrency: "unbounded" },
        );
      }),
    );
    expect(memory.notes.map((n) => n.seq)).toEqual(Array.from({ length: 25 }, (_, i) => i + 1));
    expect(new Set(memory.notes.map((n) => n.note.id)).size).toBe(25);
  });

  it("takes sentAt in the order of seq, even when commands interleave", async () => {
    const { memory, layer } = memoryStore();
    await runWith(
      layer,
      Effect.gen(function* () {
        const room = yield* RoomService;
        yield* room.dispatch(open);
        // Every read of the clock returns a later time, so a note stamped outside the lock
        // could get an earlier time than a note committed before it.
        const real = yield* Clock.Clock;
        let tick = 0;
        yield* Effect.all(
          Array.from({ length: 25 }, () => room.sendNote(alice, photo())),
          { concurrency: "unbounded" },
        ).pipe(
          Effect.provideService(Clock.Clock, {
            ...real,
            currentTimeMillis: Effect.sync(() => (tick += 1)),
            currentTimeMillisUnsafe: () => (tick += 1),
          }),
        );
      }),
    );
    const sentAt = memory.notes.map((n) => n.note.sentAt);
    expect(sentAt).toEqual([...sentAt].sort((a, b) => a - b));
  });

  it("lets a failed commit surface as a defect, with nothing stored", async () => {
    const { memory, layer } = memoryStore({ failCommit: true });
    await expect(
      runWith(
        layer,
        RoomService.use((room) => room.dispatch(open)),
      ),
    ).rejects.toThrow();
    expect(memory.state).toEqual(vacant);
  });

  it("reads notes back after a given sequence, up to a limit", async () => {
    const { layer } = memoryStore();
    const notes = await runWith(
      layer,
      Effect.gen(function* () {
        const room = yield* RoomService;
        yield* room.dispatch(open);
        yield* room.sendNote(alice, photo());
        yield* room.sendNote(bob, photo());
        yield* room.sendNote(alice, photo());
        return yield* room.notesAfter(1, 1);
      }),
    );
    expect(notes.map((n) => n.seq)).toEqual([2]);
  });

  it("answers a key it already holds with the first note, and stores nothing more", async () => {
    const { memory, layer } = memoryStore();
    const outcome = await runWith(
      layer,
      Effect.gen(function* () {
        const room = yield* RoomService;
        yield* room.dispatch(open);
        const request = photo();
        const first = yield* room.sendNote(alice, request);
        const again = yield* room.sendNote(alice, request);
        const partner = yield* room.sendNote(bob, request);
        return { first, again, partner };
      }),
    );
    expect(outcome.again._tag).toBe("Accepted");
    if (outcome.first._tag !== "Accepted" || outcome.again._tag !== "Accepted") return;
    expect(outcome.again.outputs.map((output) => output._tag)).toEqual(["NoteRepeated"]);
    expect(outcome.again.state).toEqual(outcome.first.state);
    // The partner's note under the same key is a different note.
    expect(memory.notes.map(({ seq, note }) => [seq, note.author])).toEqual([
      [1, alice],
      [2, bob],
    ]);
  });

  it("stores one note when the same key arrives many times at once", async () => {
    const { memory, layer } = memoryStore();
    await runWith(
      layer,
      Effect.gen(function* () {
        const room = yield* RoomService;
        yield* room.dispatch(open);
        const request = photo();
        yield* Effect.all(
          Array.from({ length: 25 }, () => room.sendNote(alice, request)),
          { concurrency: "unbounded" },
        );
      }),
    );
    expect(memory.notes).toHaveLength(1);
  });

  it("forgets every note of one author, keeping the partner's and the room's sequence", async () => {
    const { memory, layer } = memoryStore();
    const outcome = await runWith(
      layer,
      Effect.gen(function* () {
        const room = yield* RoomService;
        yield* room.dispatch(open);
        const repeated = photo();
        yield* room.sendNote(alice, repeated);
        yield* room.sendNote(bob, photo());
        yield* room.sendNote(alice, photo());
        const forgotten = yield* room.forgetAuthor(alice);
        // A retry of a forgotten note's key is a new note, not an answer from storage.
        const again = yield* room.sendNote(alice, repeated);
        return { forgotten, again, after: yield* room.forgetAuthor(alice) };
      }),
    );
    expect(outcome.forgotten.map(({ seq }) => seq)).toEqual([1, 3]);
    expect(outcome.after.map(({ seq }) => seq)).toEqual([4]);
    expect(memory.notes.map(({ seq, note }) => [seq, note.author])).toEqual([[2, bob]]);
  });
});
