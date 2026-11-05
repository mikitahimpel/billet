import { Effect, Layer, Option, Schema } from "effect";
import type { ActivityCursor } from "@billet/contracts-domain/activity";
import type { CatEntry } from "@billet/contracts-domain/cat";
import type { CoinEntry } from "@billet/contracts-domain/coins";
import type { SharedList } from "@billet/contracts-domain/list";
import type { NoteReaction } from "@billet/contracts-domain/reaction";
import { countsAsUnread, cursorOf, type ActivityRow } from "../src/activity.ts";
import { NoteId } from "@billet/contracts-domain/ids";
import { NoteIdSource } from "../src/note-id-source.ts";
import type { ActiveRoom, RoomState, SequencedNote } from "../src/room-state.ts";
import { RoomStore, type AppendedNote, type ListWrite } from "../src/room-store.ts";
import { vacant } from "./samples.ts";

/** An in-memory store. `load` yields after reading, so a fiber gives way before it commits. */
export const memoryStore = (options?: { readonly failCommit?: boolean }) => {
  const memory = {
    state: vacant as RoomState,
    notes: [] as Array<SequencedNote>,
    keys: new Map<string, SequencedNote>(),
    cat: [] as Array<CatEntry>,
    activity: new Map<string, ActivityRow>(),
    marks: new Map<string, ActivityCursor>(),
    coins: [] as Array<CoinEntry>,
    reactions: new Map<string, NoteReaction>(),
    lists: [] as Array<SharedList>,
    listKeys: new Set<string>(),
  };
  const newestFirst = () =>
    [...memory.activity.values()].toSorted((a, b) => (cursorOf(b) < cursorOf(a) ? -1 : 1));
  const layer = Layer.succeed(RoomStore, {
    load: Effect.sync(() => memory.state).pipe(Effect.tap(() => Effect.yieldNow)),
    commit: (
      room: ActiveRoom,
      notes: ReadonlyArray<AppendedNote>,
      catEntries: ReadonlyArray<CatEntry>,
      activity: ReadonlyArray<ActivityRow>,
      coins: ReadonlyArray<CoinEntry>,
      reactions: ReadonlyArray<NoteReaction>,
      lists: ReadonlyArray<ListWrite>,
    ) =>
      Effect.suspend(() => {
        if (options?.failCommit === true) return Effect.die("storage is down");
        memory.state = room;
        memory.cat.push(...catEntries);
        memory.coins.push(...coins);
        for (const row of activity) memory.activity.set(row.id, row);
        for (const r of reactions) memory.reactions.set(`${r.note}/${r.by}`, r);
        for (const { entry, key } of notes) {
          memory.notes.push(entry);
          memory.keys.set(`${entry.note.author}/${key}`, entry);
        }
        for (const write of lists) {
          memory.listKeys.add(write.key);
          if (write._tag === "Drop") {
            memory.lists = memory.lists.filter((list) => list.id !== write.list);
          } else if (memory.lists.some((list) => list.id === write.list.id)) {
            memory.lists = memory.lists.map((list) =>
              list.id === write.list.id ? write.list : list,
            );
          } else {
            memory.lists.push(write.list);
          }
        }
        return Effect.void;
      }),
    lists: Effect.sync(() => memory.lists),
    listById: (id) =>
      Effect.sync(() => Option.fromNullishOr(memory.lists.find((list) => list.id === id))),
    listKeyUsed: (key) => Effect.sync(() => memory.listKeys.has(key)),
    forgetLists: Effect.sync(() => {
      memory.lists = [];
      memory.listKeys.clear();
    }),
    coinEntryById: (id) =>
      Effect.sync(() => Option.fromNullishOr(memory.coins.find((entry) => entry.id === id))),
    coinEntriesAfter: (after, limit) =>
      Effect.sync(() => {
        const at = memory.coins.findIndex((entry) => entry.id === after);
        return memory.coins.slice(at + 1, at + 1 + limit);
      }),
    noteByKey: (author, key) =>
      Effect.sync(() => Option.fromNullishOr(memory.keys.get(`${author}/${key}`))),
    noteById: (id) =>
      Effect.sync(() => Option.fromNullishOr(memory.notes.find((entry) => entry.note.id === id))),
    reactionOf: (note, by) =>
      Effect.sync(() => Option.fromNullishOr(memory.reactions.get(`${note}/${by}`))),
    reactionsAfter: (afterRev, limit) =>
      Effect.sync(() =>
        [...memory.reactions.values()]
          .filter((r) => r.rev > afterRev)
          .toSorted((a, b) => a.rev - b.rev)
          .slice(0, limit),
      ),
    forgetReactions: Effect.sync(() => memory.reactions.clear()),
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
    activityBefore: (before, limit) =>
      Effect.sync(() =>
        newestFirst()
          .filter((row) => before === undefined || cursorOf(row) < before)
          .slice(0, limit),
      ),
    unreadCount: (user, mark) =>
      Effect.sync(
        () =>
          newestFirst().filter(
            (row) => (mark === undefined || cursorOf(row) > mark) && countsAsUnread(row, user),
          ).length,
      ),
    readMark: (user) => Effect.sync(() => Option.fromNullishOr(memory.marks.get(user))),
    saveReadMark: (user, mark) => Effect.sync(() => void memory.marks.set(user, mark)),
    forgetActivity: Effect.sync(() => {
      memory.activity.clear();
      memory.marks.clear();
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
