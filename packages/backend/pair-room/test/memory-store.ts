import { Effect, Layer, Option, Schema } from "effect";
import type { CatEntry } from "@billet/contracts-domain/cat";
import { NoteId } from "@billet/contracts-domain/ids";
import { NoteIdSource } from "../src/note-id-source.ts";
import type { ActiveRoom, RoomState, SequencedNote } from "../src/room-state.ts";
import { RoomStore, type AppendedNote } from "../src/room-store.ts";
import { vacant } from "./samples.ts";

/** An in-memory store. `load` yields after reading, so a fiber gives way before it commits. */
export const memoryStore = (options?: { readonly failCommit?: boolean }) => {
  const memory = {
    state: vacant as RoomState,
    notes: [] as Array<SequencedNote>,
    keys: new Map<string, SequencedNote>(),
    cat: [] as Array<CatEntry>,
  };
  const layer = Layer.succeed(RoomStore, {
    load: Effect.sync(() => memory.state).pipe(Effect.tap(() => Effect.yieldNow)),
    commit: (
      room: ActiveRoom,
      notes: ReadonlyArray<AppendedNote>,
      catEntries: ReadonlyArray<CatEntry>,
    ) =>
      Effect.suspend(() => {
        if (options?.failCommit === true) return Effect.die("storage is down");
        memory.state = room;
        memory.cat.push(...catEntries);
        for (const { entry, key } of notes) {
          memory.notes.push(entry);
          memory.keys.set(`${entry.note.author}/${key}`, entry);
        }
        return Effect.void;
      }),
    noteByKey: (author, key) =>
      Effect.sync(() => Option.fromNullishOr(memory.keys.get(`${author}/${key}`))),
    notesAfter: (afterSeq: number, limit: number) =>
      Effect.sync(() => memory.notes.filter((n) => n.seq > afterSeq).slice(0, limit)),
    catEntryById: (id) =>
      Effect.sync(() => Option.fromNullishOr(memory.cat.find((entry) => entry.id === id))),
    catEntriesAfter: (afterSeq: number, limit: number) =>
      Effect.sync(() => memory.cat.filter((e) => e.seq > afterSeq).slice(0, limit)),
    catEntriesSince: (since: number) => Effect.sync(() => memory.cat.filter((e) => e.at >= since)),
    forgetCat: Effect.sync(() => {
      memory.cat = [];
      if (memory.state._tag === "Active") {
        const { cat: _, ...rest } = memory.state;
        memory.state = rest;
      }
    }),
    forgetAuthor: (author) =>
      Effect.sync(() => {
        const forgotten = memory.notes.filter((entry) => entry.note.author === author);
        memory.notes = memory.notes.filter((entry) => entry.note.author !== author);
        for (const [key, entry] of memory.keys) {
          if (entry.note.author === author) memory.keys.delete(key);
        }
        return forgotten;
      }),
  });
  return { memory, layer };
};

export const countingIds = () => {
  let next = 0;
  return Layer.succeed(NoteIdSource, {
    next: Effect.sync(() => Schema.decodeUnknownSync(NoteId)(`note-${(next += 1)}`)),
  });
};
