import { Clock, Effect, Layer, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { NoteId } from "@billet/contracts-domain/ids";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { NoteIdSource } from "../src/note-id-source.ts";
import { RoomCommand } from "../src/room-command.ts";
import { RoomService } from "../src/room-service.ts";
import type { ActiveRoom, RoomState, SequencedNote } from "../src/room-state.ts";
import { RoomStore } from "../src/room-store.ts";
import { active, alice, bob, image, mallory, pairId, vacant } from "./samples.ts";

/** An in-memory store. `load` yields after reading, so a fiber gives way before it commits. */
const memoryStore = (options?: { readonly failCommit?: boolean }) => {
  const memory = {
    state: vacant as RoomState,
    notes: [] as Array<SequencedNote>,
  };
  const layer = Layer.succeed(RoomStore, {
    load: Effect.sync(() => memory.state).pipe(Effect.tap(() => Effect.yieldNow)),
    commit: (room: ActiveRoom, notes: ReadonlyArray<SequencedNote>) =>
      Effect.suspend(() => {
        if (options?.failCommit === true) return Effect.die("storage is down");
        memory.state = room;
        memory.notes.push(...notes);
        return Effect.void;
      }),
    notesAfter: (afterSeq: number, limit: number) =>
      Effect.sync(() => memory.notes.filter((n) => n.seq > afterSeq).slice(0, limit)),
  });
  return { memory, layer };
};

const countingIds = () => {
  let next = 0;
  return Layer.succeed(NoteIdSource, {
    next: Effect.sync(() => Schema.decodeUnknownSync(NoteId)(`note-${(next += 1)}`)),
  });
};

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
const photo = SendNoteRequest.cases.Photo.make({ image });

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
        return yield* room.sendNote(alice, photo);
      }).pipe(Effect.provide(TestClock.layer())),
    );
    const note = {
      _tag: "Photo",
      id: "note-1",
      author: alice,
      sentAt: 1_700_000_000_000,
      image,
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
        yield* room.sendNote(bob, SendNoteRequest.cases.Drawing.make({ compact, image }));
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
        return yield* room.sendNote(mallory, photo);
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
          Array.from({ length: 25 }, () => room.sendNote(alice, photo)),
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
          Array.from({ length: 25 }, () => room.sendNote(alice, photo)),
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
        yield* room.sendNote(alice, photo);
        yield* room.sendNote(bob, photo);
        yield* room.sendNote(alice, photo);
        return yield* room.notesAfter(1, 1);
      }),
    );
    expect(notes.map((n) => n.seq)).toEqual([2]);
  });
});
