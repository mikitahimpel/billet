import { shopOf } from "@billet/backend-pair-room/shop-view";
import { Effect, Layer, Option, Schema } from "effect";
import { SecureRandom } from "effect/crypto";
import type { ActivityCursor } from "@billet/contracts-domain/activity";
import type { CatEntry } from "@billet/contracts-domain/cat";
import type { CoinEntry } from "@billet/contracts-domain/coins";
import type { NoteReaction } from "@billet/contracts-domain/reaction";
import { countsAsUnread, cursorOf, type ActivityRow } from "@billet/backend-pair-room/activity";
import { NoteId, UserId, type MediaKey } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { Metrics, type MetricEvent } from "@billet/backend-metrics/metrics";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import { NoteIdSource } from "@billet/backend-pair-room/note-id-source";
import { RoomService } from "@billet/backend-pair-room/room-service";
import type { ActiveRoom, RoomState, SequencedNote } from "@billet/backend-pair-room/room-state";
import { RoomStore, type AppendedNote } from "@billet/backend-pair-room/room-store";
import { MediaStore, mediaPrefix } from "../src/media-store.ts";
import { PairRooms } from "../src/pair-rooms.ts";

export const user = Schema.decodeSync(UserId);
export const pair = Schema.decodeSync(PairId);

/** The real room rules on memory. */
const makeRoom = () => {
  let state: RoomState = { _tag: "Vacant" };
  let notes: Array<SequencedNote> = [];
  let nextNote = 0;
  let cat: Array<CatEntry> = [];
  const coins: Array<CoinEntry> = [];
  const activity = new Map<string, ActivityRow>();
  const marks = new Map<string, ActivityCursor>();
  const newestFirst = () =>
    [...activity.values()].toSorted((a, b) => (cursorOf(b) < cursorOf(a) ? -1 : 1));
  const keys = new Map<string, SequencedNote>();
  const reactions = new Map<string, NoteReaction>();
  const store = Layer.succeed(RoomStore, {
    load: Effect.sync(() => state),
    commit: (
      room: ActiveRoom,
      appended: ReadonlyArray<AppendedNote>,
      catEntries: ReadonlyArray<CatEntry>,
      rows: ReadonlyArray<ActivityRow>,
      coinEntries: ReadonlyArray<CoinEntry>,
      changed: ReadonlyArray<NoteReaction>,
    ) =>
      Effect.sync(() => {
        state = room;
        for (const r of changed) reactions.set(`${r.note}/${r.by}`, r);
        cat.push(...catEntries);
        coins.push(...coinEntries);
        for (const row of rows) activity.set(row.id, row);
        for (const { entry, key } of appended) {
          notes.push(entry);
          keys.set(`${entry.note.author}/${key}`, entry);
        }
      }),
    noteByKey: (author, key) =>
      Effect.sync(() => Option.fromNullishOr(keys.get(`${author}/${key}`))),
    notesAfter: (afterSeq: number, limit: number) =>
      Effect.sync(() => notes.filter(({ seq }) => seq > afterSeq).slice(0, limit)),
    noteById: (id) => Effect.sync(() => Option.fromNullishOr(notes.find((e) => e.note.id === id))),
    reactionOf: (note, by) =>
      Effect.sync(() => Option.fromNullishOr(reactions.get(`${note}/${by}`))),
    reactionsAfter: (afterRev, limit) =>
      Effect.sync(() =>
        [...reactions.values()]
          .filter((r) => r.rev > afterRev)
          .toSorted((a, b) => a.rev - b.rev)
          .slice(0, limit),
      ),
    forgetReactions: Effect.sync(() => reactions.clear()),
    coinEntryById: (id) => Effect.sync(() => Option.fromNullishOr(coins.find((e) => e.id === id))),
    coinEntriesAfter: (after, limit) =>
      Effect.sync(() => {
        const at = coins.findIndex((e) => e.id === after);
        return coins.slice(at + 1, at + 1 + limit);
      }),
    catEntryById: (id) => Effect.sync(() => Option.fromNullishOr(cat.find((e) => e.id === id))),
    catEntriesAfter: (afterSeq: number, limit: number) =>
      Effect.sync(() => cat.filter(({ seq }) => seq > afterSeq).slice(0, limit)),
    catEntriesSince: (since: number) => Effect.sync(() => cat.filter(({ at }) => at >= since)),
    forgetCat: Effect.sync(() => {
      cat = [];
      if (state._tag === "Active") {
        const { cat: _, ...rest } = state;
        state = rest;
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
    readMark: (user) => Effect.sync(() => Option.fromNullishOr(marks.get(user))),
    saveReadMark: (user, mark) => Effect.sync(() => void marks.set(user, mark)),
    forgetActivity: Effect.sync(() => {
      activity.clear();
      marks.clear();
    }),
    forgetAuthor: (author) =>
      Effect.sync(() => {
        const forgotten = notes.filter(({ note }) => note.author === author);
        notes = notes.filter(({ note }) => note.author !== author);
        for (const [key, entry] of keys) if (entry.note.author === author) keys.delete(key);
        return forgotten;
      }),
  });
  const ids = Layer.succeed(NoteIdSource, {
    next: Effect.sync(() => Schema.decodeSync(NoteId)(`note-${(nextNote += 1)}`)),
  });
  return Effect.runSync(RoomService.make.pipe(Effect.provide(Layer.merge(store, ids))));
};

/** Memory-backed dependencies for the given couples. `pairs` is `[pairId, first, second]`. */
export const makeWorld = (pairs: ReadonlyArray<readonly [PairId, UserId, UserId]>) => {
  const objects = new Map<MediaKey, Uint8Array>();
  const rooms = new Map<PairId, ReturnType<typeof makeRoom>>();
  const recorded: Array<MetricEvent> = [];

  const roomOf = (pairId: PairId) => {
    const room = rooms.get(pairId) ?? makeRoom();
    rooms.set(pairId, room);
    return room;
  };

  const repository: PairingRepository["Service"] = {
    ...makeInMemoryPairingRepository().repository,
    findPair: (userId) =>
      Effect.succeed(
        Option.fromNullishOr(pairs.find(([, ...members]) => members.includes(userId))?.[0]),
      ),
    findMembers: (pairId) =>
      Effect.sync(() => {
        const row = pairs.find(([id]) => id === pairId);
        return row === undefined ? [] : [row[1], row[2]];
      }),
  };

  const uploaders = new Map<MediaKey, UserId>();
  const media: MediaStore["Service"] = {
    put: (key, bytes, uploader) =>
      Effect.sync(() => {
        objects.set(key, bytes);
        uploaders.set(key, uploader);
      }),
    get: (key) => Effect.sync(() => Option.fromNullishOr(objects.get(key))),
    has: (key) => Effect.sync(() => objects.has(key)),
    uploadedBy: (pairId, uploader) =>
      Effect.sync(() =>
        [...objects.keys()].filter(
          (key) => key.startsWith(mediaPrefix(pairId)) && uploaders.get(key) === uploader,
        ),
      ),
    remove: (keys) =>
      Effect.sync(() => {
        for (const key of keys) {
          objects.delete(key);
          uploaders.delete(key);
        }
      }),
  };

  const pairRooms: PairRooms["Service"] = {
    open: (pairId, members, joined) =>
      roomOf(pairId).dispatch(
        joined === undefined
          ? { _tag: "Open", pairId, members }
          : { _tag: "Open", pairId, members, joined },
      ),
    sendNote: (pairId, author, request) => roomOf(pairId).sendNote(author, request),
    inks: (pairId) =>
      roomOf(pairId).state.pipe(Effect.map((state) => (state._tag === "Active" ? state.inks : []))),
    grantInks: (pairId, inks) => roomOf(pairId).dispatch({ _tag: "GrantInks", inks }),
    coins: (pairId, after, limit) =>
      Effect.all([roomOf(pairId).state, roomOf(pairId).coinEntriesAfter(after, limit)]).pipe(
        Effect.map(([state, entries]) => ({
          balance: state._tag === "Active" ? state.wallet.balance : 0,
          entries,
        })),
      ),
    buy: (pairId, by, id, ink) => roomOf(pairId).buy(by, id, ink),
    shop: (pairId) => roomOf(pairId).state.pipe(Effect.map(shopOf)),
    order: (pairId, by, id, offer) => roomOf(pairId).order(by, id, offer),
    setWish: (pairId, by, item, wished) => roomOf(pairId).setWish(by, item, wished),
    notesAfter: (pairId, afterSeq, limit) => roomOf(pairId).notesAfter(afterSeq, limit),
    forgetMember: (pairId, user) => roomOf(pairId).forgetAuthor(user),
    endSessions: () => Effect.void,
    saveCat: (pairId, user, request, seed) => roomOf(pairId).saveCat(user, request, seed),
    recordCatEvent: (pairId, user, request) => roomOf(pairId).recordCatEvent(user, request),
    cat: (pairId) => roomOf(pairId).catView,
    catJournal: (pairId, afterSeq, limit) => roomOf(pairId).catEntriesAfter(afterSeq, limit),
    react: (pairId, by, request) => roomOf(pairId).react(by, request),
    reactions: (pairId, afterRev, limit) => roomOf(pairId).reactionsAfter(afterRev, limit),
    activity: (pairId, caller, before, limit) => roomOf(pairId).activityPage(caller, before, limit),
    markActivityRead: (pairId, user, upTo) => roomOf(pairId).markActivityRead(user, upTo),
  };

  return {
    objects,
    recorded,
    media,
    pairRooms,
    repository,
    layer: Layer.mergeAll(
      Layer.succeed(PairingRepository, repository),
      Layer.succeed(MediaStore, media),
      Layer.succeed(PairRooms, pairRooms),
      Layer.succeed(Metrics, { record: (event) => Effect.sync(() => void recorded.push(event)) }),
      SecureRandom.layerWebCrypto,
    ),
  };
};
