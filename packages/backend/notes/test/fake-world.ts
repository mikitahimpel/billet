import { InMemoryShopStore } from "@billet/backend-shop/test/in-memory-shop-store";
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
import {
  applyGiftWrites,
  type GiftRows,
  GiftsRoom,
  GiftsStore,
} from "@billet/backend-pair-room/gifts";
import {
  type PickRow,
  PickTonightRoom,
  PickTonightStore,
  pickKeyOf,
} from "@billet/backend-pair-room/pick-tonight";
import {
  GuessDeck,
  type GuessAnswerRow,
  GuessRoom,
  type GuessRoundRow,
  GuessStore,
  type GuessWeekRow,
  withScore,
} from "@billet/backend-pair-room/guess";
import { RoomService } from "@billet/backend-pair-room/room-service";
import { RiddleRoom, RiddleStore } from "@billet/backend-pair-room/riddle";
import {
  endedAt,
  noRiddleSeries,
  type RiddleGuessRow,
  type RiddleRow,
  type RiddleWrite,
} from "@billet/backend-pair-room/riddle-rules";
import { GuessQuestionId } from "@billet/contracts-domain/guess";
import type { ActiveRoom, RoomState, SequencedNote } from "@billet/backend-pair-room/room-state";
import { RoomStore, type AppendedNote, type ListWrite } from "@billet/backend-pair-room/room-store";
import type { SharedList } from "@billet/contracts-domain/list";
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
  let lists: Array<SharedList> = [];
  const listKeys = new Set<string>();
  const riddles = new Map<string, RiddleRow>();
  const riddleGuesses = new Map<string, RiddleGuessRow>();
  let riddleSeries = noRiddleSeries;
  const store = Layer.succeed(RoomStore, {
    lists: Effect.sync(() => lists),
    listById: (id) => Effect.sync(() => Option.fromNullishOr(lists.find((list) => list.id === id))),
    listKeyUsed: (key) => Effect.sync(() => listKeys.has(key)),
    forgetLists: Effect.sync(() => {
      lists = [];
      listKeys.clear();
    }),
    load: Effect.sync(() => state),
    commit: (
      room: ActiveRoom,
      appended: ReadonlyArray<AppendedNote>,
      catEntries: ReadonlyArray<CatEntry>,
      rows: ReadonlyArray<ActivityRow>,
      coinEntries: ReadonlyArray<CoinEntry>,
      changed: ReadonlyArray<NoteReaction>,
      listWrites: ReadonlyArray<ListWrite>,
      riddleWrites: ReadonlyArray<RiddleWrite>,
    ) =>
      Effect.sync(() => {
        state = room;
        for (const { riddle, guess, series } of riddleWrites) {
          riddles.set(riddle.id, riddle);
          if (guess !== undefined) riddleGuesses.set(`${guess.riddle}/${guess.key}`, guess);
          if (series !== undefined) riddleSeries = series;
        }
        for (const write of listWrites) {
          listKeys.add(write.key);
          const id = write._tag === "Put" ? write.list.id : write.list;
          const rest = lists.filter((list) => list.id !== id);
          const at = lists.findIndex((list) => list.id === id);
          lists =
            write._tag === "Drop"
              ? rest
              : at === -1
                ? [...lists, write.list]
                : lists.map((list) => (list.id === id ? write.list : list));
        }
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
    forgetMoods: Effect.sync(() => {
      if (state._tag === "Active") state = { ...state, moods: [] };
    }),
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
  let giftRows: GiftRows = { wishes: [], plans: [], loves: [] };
  const giftsStore = Layer.succeed(GiftsStore, {
    load: Effect.sync(() => giftRows),
    apply: (writes) => Effect.sync(() => void (giftRows = applyGiftWrites(giftRows, writes))),
    forget: Effect.sync(() => void (giftRows = { wishes: [], plans: [], loves: [] })),
  });
  let swipes: Array<PickRow> = [];
  const pickStore = Layer.succeed(PickTonightStore, {
    since: (since) => Effect.sync(() => swipes.filter((row) => row.at >= since)),
    put: (row, pruneBefore) =>
      Effect.sync(() => {
        const key = pickKeyOf(row.title);
        swipes = [
          ...swipes.filter(
            (old) =>
              old.at >= pruneBefore && !(old.member === row.member && pickKeyOf(old.title) === key),
          ),
          row,
        ];
      }),
    forget: Effect.sync(() => void (swipes = [])),
  });
  let rounds: Array<GuessRoundRow> = [];
  let answers: Array<GuessAnswerRow> = [];
  let weeks: ReadonlyArray<GuessWeekRow> = [];
  const guessStore = Layer.succeed(GuessStore, {
    round: (day) => Effect.sync(() => Option.fromNullishOr(rounds.find((r) => r.day === day))),
    rounds: Effect.sync(() => rounds),
    startRound: (round) =>
      Effect.sync(() => {
        if (!rounds.some((r) => r.day === round.day)) rounds = [...rounds, round];
      }),
    answers: (day) => Effect.sync(() => answers.filter((answer) => answer.day === day)),
    weeks: Effect.sync(() => weeks),
    answer: (row, score) =>
      Effect.sync(() => {
        answers = [...answers, row];
        if (score !== undefined) weeks = withScore(weeks, score);
      }),
    forget: Effect.sync(() => {
      rounds = [];
      answers = [];
      weeks = [];
    }),
  });
  const deck = Layer.succeed(GuessDeck, {
    questions: [1, 2, 3, 4, 5, 6, 7].map((id) => Schema.decodeSync(GuessQuestionId)(id)),
  });
  const room = Effect.runSync(RoomService.make.pipe(Effect.provide(Layer.merge(store, ids))));
  const guess = Effect.runSync(
    GuessRoom.make.pipe(
      Effect.provide(
        Layer.mergeAll(store, guessStore, deck, Layer.succeed(RoomService, RoomService.of(room))),
      ),
    ),
  );
  const riddleStore = Layer.succeed(RiddleStore, {
    byId: (id) => Effect.sync(() => Option.fromNullishOr(riddles.get(id))),
    open: Effect.sync(() => [...riddles.values()].filter((row) => endedAt(row) === undefined)),
    ended: (limit) =>
      Effect.sync(() =>
        [...riddles.values()]
          .filter((row) => endedAt(row) !== undefined)
          .toSorted((a, b) => (endedAt(b) ?? 0) - (endedAt(a) ?? 0))
          .slice(0, limit),
      ),
    guess: (riddle, key) =>
      Effect.sync(() => Option.fromNullishOr(riddleGuesses.get(`${riddle}/${key}`))),
    series: Effect.sync(() => riddleSeries),
    forget: Effect.sync(() => {
      riddles.clear();
      riddleGuesses.clear();
      riddleSeries = noRiddleSeries;
    }),
  });
  const riddle = Effect.runSync(
    RiddleRoom.make.pipe(
      Effect.provide(
        Layer.mergeAll(store, riddleStore, Layer.succeed(RoomService, RoomService.of(room))),
      ),
    ),
  );
  const gifts = Effect.runSync(GiftsRoom.make.pipe(Effect.provide(Layer.merge(store, giftsStore))));
  const pick = Effect.runSync(
    PickTonightRoom.make.pipe(Effect.provide(Layer.merge(store, pickStore))),
  );
  return { ...room, gifts, pick, guess, riddle };
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
    removeAll: (pairId) =>
      Effect.sync(() => {
        for (const key of objects.keys()) {
          if (!key.startsWith(mediaPrefix(pairId))) continue;
          objects.delete(key);
          uploaders.delete(key);
        }
      }),
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
    grantItems: (pairId, items) => roomOf(pairId).dispatch({ _tag: "GrantItems", items }),
    coins: (pairId, after, limit) =>
      Effect.all([roomOf(pairId).settled, roomOf(pairId).coinEntriesAfter(after, limit)]).pipe(
        Effect.map(([state, entries]) =>
          state._tag === "Active" ? { balance: state.wallet.balance, entries } : null,
        ),
      ),
    buy: (pairId, by, id, ink, terms) => roomOf(pairId).buy(by, id, ink, terms),
    shop: (pairId) =>
      roomOf(pairId).settled.pipe(
        Effect.map((state) => (state._tag === "Active" ? shopOf(state) : null)),
      ),
    order: (pairId, by, id, offer, utcOffsetSeconds, terms) =>
      roomOf(pairId).order(by, id, offer, utcOffsetSeconds, terms),
    openGift: (pairId, by, utcOffsetSeconds) => roomOf(pairId).openGift(by, utcOffsetSeconds),
    claimBonus: (pairId, by, collection) => roomOf(pairId).claimBonus(by, collection),
    earn: (pairId, by, event, utcOffsetSeconds) => roomOf(pairId).earn(by, event, utcOffsetSeconds),
    creditPurchase: (pairId, credit) => roomOf(pairId).creditPurchase(credit),
    changeLayout: (pairId, by, id, change) => roomOf(pairId).changeLayout(by, id, change),
    setWish: (pairId, by, item, wished, offered) =>
      roomOf(pairId).setWish(by, item, wished, offered),
    notesAfter: (pairId, afterSeq, limit) => roomOf(pairId).notesAfter(afterSeq, limit),
    forgetMember: (pairId, user) => roomOf(pairId).forgetAuthor(user),
    destroy: () => Effect.void,
    endSessions: () => Effect.void,
    saveCat: (pairId, user, request, seed) => roomOf(pairId).saveCat(user, request, seed),
    recordCatEvent: (pairId, user, request) => roomOf(pairId).recordCatEvent(user, request),
    cat: (pairId) => roomOf(pairId).catView,
    catJournal: (pairId, afterSeq, limit) => roomOf(pairId).catEntriesAfter(afterSeq, limit),
    react: (pairId, by, request) => roomOf(pairId).react(by, request),
    reactions: (pairId, afterRev, limit) => roomOf(pairId).reactionsAfter(afterRev, limit),
    activity: (pairId, caller, before, limit) => roomOf(pairId).activityPage(caller, before, limit),
    markActivityRead: (pairId, user, upTo) => roomOf(pairId).markActivityRead(user, upTo),
    setMood: (pairId, by, request) => roomOf(pairId).setMood(by, request),
    moods: (pairId) => roomOf(pairId).moods,
    recordStreakDay: (pairId, by, request) => roomOf(pairId).recordStreakDay(by, request),
    restoreStreak: (pairId, by, request) => roomOf(pairId).restoreStreak(by, request),
    streak: (pairId) => roomOf(pairId).streak,
    gifts: (pairId, by, command) => roomOf(pairId).gifts.run(by, command),
    pickTonight: (pairId, by, command) => roomOf(pairId).pick.run(by, command),
    riddle: (pairId, by, command) =>
      roomOf(pairId)
        .riddle.run(by, command)
        .pipe(Effect.map(({ result }) => result)),
    guess: (pairId, by, command) =>
      roomOf(pairId)
        .guess.run(by, command)
        .pipe(Effect.map(({ result }) => result)),
    lists: (pairId, by, request) =>
      roomOf(pairId)
        .listsFor(by, request)
        .pipe(Effect.map(({ result }) => result)),
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
      InMemoryShopStore(),
      Layer.succeed(Metrics, { record: (event) => Effect.sync(() => void recorded.push(event)) }),
      SecureRandom.layerWebCrypto,
    ),
  };
};
