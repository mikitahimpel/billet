import { and, asc, count, desc, eq, gt, gte, isNull, lt, max, ne, or, sql } from "drizzle-orm";
import { Context, Effect, Layer, Option, Schema } from "effect";
import { ActivityCursor, ActivityEvent, ActivityTarget } from "@billet/contracts-domain/activity";
import { CatEntry, CatEvent } from "@billet/contracts-domain/cat";
import { CoinEntry, type CoinEntryId } from "@billet/contracts-domain/coins";
import type { EpochMillis, IdempotencyKey, NoteId, UserId } from "@billet/contracts-domain/ids";
import { type ListId, ListItem, SharedList } from "@billet/contracts-domain/list";
import { Note } from "@billet/contracts-domain/note";
import { NoteReaction } from "@billet/contracts-domain/reaction";
import { MoodCheckIn } from "@billet/contracts-domain/mood";
import {
  RoomState,
  type ActiveRoom,
  type SequencedNote,
} from "@billet/backend-pair-room/room-state";
import { ActivityRow, activityRetentionMillis, cursorOf } from "@billet/backend-pair-room/activity";
import { RoomStore, type AppendedNote, type ListWrite } from "@billet/backend-pair-room/room-store";
import type { RiddleWrite } from "@billet/backend-pair-room/riddle-rules";
import type { RoomDatabase } from "./room-database.ts";
import { writeRiddle } from "./pair-room-riddle-write.ts";
import {
  activity,
  activityRead,
  cat,
  catEntry,
  claimedBonus,
  coinEntry,
  listItems,
  listKeys,
  lists,
  mood,
  note,
  ownedInk,
  layoutLog,
  ownedItem,
  placement,
  reaction,
  room,
  wallet,
  wish,
} from "./room-schema.ts";

/** The Drizzle handle of the Durable Object that owns this runtime, already migrated. */
export class RoomDb extends Context.Service<RoomDb, RoomDatabase>()(
  "@billet/backend-platform/RoomDb",
) {}

const NoteJson = Schema.fromJsonString(Note);
const encodeNote = Schema.encodeSync(NoteJson);
const decodeNoteOption = Schema.decodeOption(NoteJson);

/** A smaller, zero or negative `limit` is honoured; a page is never unbounded. */
export const MAX_NOTES_PER_PAGE = 100;
const pageSize = (limit: number): number =>
  Math.max(0, Math.min(Math.trunc(limit), MAX_NOTES_PER_PAGE));
const decodeRoom = Schema.decodeUnknownSync(RoomState);

type RoomRow = typeof room.$inferSelect;
type CatRow = typeof cat.$inferSelect;
type CatEntryRow = typeof catEntry.$inferSelect;
type WalletRow = typeof wallet.$inferSelect;
type PlacementRow = typeof placement.$inferSelect;

const decodeCoinEntry = Schema.decodeUnknownOption(CoinEntry);

/** A row this code cannot read, such as a kind a newer build added, is left out. */
const coinEntriesFrom = (rows: ReadonlyArray<typeof coinEntry.$inferSelect>) =>
  rows.flatMap(({ id, kind, amount, ref, at }) =>
    Option.toArray(decodeCoinEntry({ id, kind, amount, ref, at })),
  );

const walletFrom = (row: WalletRow | undefined) =>
  row === undefined
    ? { balance: 0, care: 0, notes: 0, games: 0, lists: 0 }
    : {
        balance: row.balance,
        ...(row.day === null ? {} : { day: row.day }),
        care: row.care,
        notes: row.notes,
        games: row.games,
        lists: row.lists,
      };

const walletValues = ({ wallet: w }: ActiveRoom): typeof wallet.$inferInsert => ({
  id: 1,
  balance: w.balance,
  day: w.day ?? null,
  care: w.care,
  notes: w.notes,
  games: w.games,
  lists: w.lists,
});

const decodeReaction = Schema.decodeUnknownOption(NoteReaction);

/** A row this code cannot read, such as a reaction a newer build added, is left out. */
const reactionsFrom = (rows: ReadonlyArray<typeof reaction.$inferSelect>) =>
  rows.flatMap((row) =>
    Option.toArray(
      decodeReaction({
        rev: row.rev,
        note: row.noteId,
        by: row.by,
        at: row.at,
        ...(row.reaction === null ? {} : { reaction: row.reaction }),
      }),
    ),
  );

const decodeMood = Schema.decodeUnknownOption(MoodCheckIn);

/** A row this code cannot read, such as a mood a newer build added, is left out. */
const moodsFrom = (rows: ReadonlyArray<typeof mood.$inferSelect>) =>
  rows.flatMap((row) =>
    Option.toArray(
      decodeMood({
        user: row.user,
        mood: row.mood,
        ...(row.note === null ? {} : { note: row.note }),
        at: row.at,
      }),
    ),
  );

const CatEventJson = Schema.fromJsonString(CatEvent);
const encodeCatEvent = Schema.encodeSync(CatEventJson);
const decodeCatEntryOption = Schema.decodeUnknownOption(CatEntry);
const decodeCatEventJson = Schema.decodeOption(CatEventJson);

type ActivityRecord = typeof activity.$inferSelect;

const ActivityBodyJson = Schema.fromJsonString(
  Schema.Struct({ event: ActivityEvent, target: Schema.optionalKey(ActivityTarget) }),
);
const encodeActivityBody = Schema.encodeSync(ActivityBodyJson);
const decodeActivityRow = Schema.decodeUnknownOption(ActivityRow);
const decodeActivityBody = Schema.decodeOption(ActivityBodyJson);
const decodeCursorOption = Schema.decodeUnknownOption(ActivityCursor);

const activityValues = (row: ActivityRow): typeof activity.$inferInsert => ({
  id: row.id,
  sortKey: cursorOf(row),
  at: row.at,
  doerKind: row.doer._tag,
  doerUser: row.doer._tag === "Member" ? row.doer.user : null,
  body: encodeActivityBody({
    event: row.event,
    ...(row.target === undefined ? {} : { target: row.target }),
  }),
});

/** An item this code cannot read, such as a kind a newer build added, is left out. */
const activityFrom = (record: ActivityRecord): Option.Option<ActivityRow> =>
  Option.flatMap(decodeActivityBody(record.body), (body) =>
    decodeActivityRow({
      id: record.id,
      at: record.at,
      doer:
        record.doerUser === null
          ? { _tag: record.doerKind }
          : { _tag: "Member", user: record.doerUser },
      ...body,
    }),
  );

type ListRow = typeof lists.$inferSelect;
type ListItemRow = typeof listItems.$inferSelect;

const IdsJson = Schema.fromJsonString(Schema.Array(Schema.String));
const encodeIds = Schema.encodeSync(IdsJson);
const decodeIds = Schema.decodeOption(IdsJson);
const decodeListItem = Schema.decodeUnknownOption(ListItem);
const decodeList = Schema.decodeUnknownOption(SharedList);

const listItemValues = (
  list: ListId,
  position: number,
  item: ListItem,
): typeof listItems.$inferInsert => ({
  id: item.id,
  listId: list,
  position,
  text: item.text,
  author: item.author,
  addedAt: item.addedAt,
  doneBy: item.doneBy ?? null,
  doneAt: item.doneAt ?? null,
  quantity: item.quantity ?? null,
  note: item.note ?? null,
  icon: item.icon ?? null,
  aisle: item.aisle ?? null,
  mediaKind: item.media?.kind ?? null,
  mediaTmdb: item.media?.tmdb ?? null,
  mediaYear: item.media?.year ?? null,
  mediaPoster: item.media?.posterPath ?? null,
  country: item.country ?? null,
  place: item.place ?? null,
  visitedIn: item.visitedIn ?? null,
  moments: item.moments === undefined ? null : encodeIds(item.moments),
  wants: encodeIds(item.wants),
});

/** An item this code cannot read, such as one a newer build wrote, is left out. */
const listItemFrom = (row: ListItemRow): Option.Option<ListItem> =>
  Option.flatMap(decodeIds(row.wants), (wants) =>
    decodeListItem({
      id: row.id,
      text: row.text,
      author: row.author,
      addedAt: row.addedAt,
      ...(row.doneBy === null || row.doneAt === null
        ? {}
        : { doneBy: row.doneBy, doneAt: row.doneAt }),
      ...(row.quantity === null ? {} : { quantity: row.quantity }),
      ...(row.note === null ? {} : { note: row.note }),
      ...(row.icon === null ? {} : { icon: row.icon }),
      ...(row.aisle === null ? {} : { aisle: row.aisle }),
      ...(row.mediaKind === null || row.mediaTmdb === null
        ? {}
        : {
            media: {
              kind: row.mediaKind,
              tmdb: row.mediaTmdb,
              ...(row.mediaYear === null ? {} : { year: row.mediaYear }),
              ...(row.mediaPoster === null ? {} : { posterPath: row.mediaPoster }),
            },
          }),
      ...(row.country === null ? {} : { country: row.country }),
      ...(row.place === null ? {} : { place: row.place }),
      ...(row.visitedIn === null ? {} : { visitedIn: row.visitedIn }),
      ...(row.moments === null ? {} : { moments: Option.getOrUndefined(decodeIds(row.moments)) }),
      wants,
    }),
  );

/** Each in its stored order. A list this code cannot read is left out. */
const listsFrom = (
  rows: ReadonlyArray<ListRow>,
  items: ReadonlyArray<ListItemRow>,
): ReadonlyArray<SharedList> =>
  rows.flatMap((row) =>
    Option.toArray(
      decodeList({
        id: row.id,
        kind: row.kind,
        title: row.title,
        icon: { symbol: row.iconSymbol, tint: row.iconTint },
        items: items
          .filter((item) => item.listId === row.id)
          .flatMap((item) => Option.toArray(listItemFrom(item))),
      }),
    ),
  );

const listKeyRetentionMillis = activityRetentionMillis;

const catFrom = (row: CatRow | undefined) =>
  row === undefined
    ? {}
    : {
        cat: {
          profile: {
            name: row.name,
            look: { model: row.model, coat: row.coat },
            bornAt: row.bornAt,
            natureSeed: row.natureSeed,
            utcOffsetSeconds: row.utcOffsetSeconds,
          },
          temper: { curious: row.curious, lazy: row.lazy, cuddly: row.cuddly },
          lastSeq: row.lastSeq,
          ...(row.lastAt === null ? {} : { lastAt: row.lastAt }),
        },
      };

const catValues = (state: ActiveRoom): typeof cat.$inferInsert | undefined => {
  if (state.cat === undefined) return undefined;
  const { profile, temper, lastSeq, lastAt } = state.cat;
  return {
    id: 1,
    name: profile.name,
    model: profile.look.model,
    coat: profile.look.coat,
    bornAt: profile.bornAt,
    natureSeed: profile.natureSeed,
    utcOffsetSeconds: profile.utcOffsetSeconds,
    curious: temper.curious,
    lazy: temper.lazy,
    cuddly: temper.cuddly,
    lastSeq,
    lastAt: lastAt ?? null,
  };
};

/** A row this code cannot read, such as an event a newer build added, is left out. */
const catEntryFrom = (row: CatEntryRow): Option.Option<CatEntry> =>
  Option.flatMap(decodeCatEventJson(row.body), (event) =>
    decodeCatEntryOption({ seq: row.seq, id: row.id, by: row.by, at: row.at, event }),
  );

const catEntriesFrom = (rows: ReadonlyArray<CatEntryRow>): ReadonlyArray<CatEntry> =>
  rows.flatMap((row) => Option.toArray(catEntryFrom(row)));

const roomFrom = (
  row: RoomRow | undefined,
  catRow: CatRow | undefined,
  inks: ReadonlyArray<string>,
  items: ReadonlyArray<string>,
  wishlist: ReadonlyArray<string>,
  walletRow: WalletRow | undefined,
  bonuses: ReadonlyArray<string>,
  moods: ReadonlyArray<MoodCheckIn>,
  layout: ReadonlyArray<PlacementRow>,
  layoutIds: ReadonlyArray<string>,
): RoomState =>
  decodeRoom(
    row === undefined
      ? { _tag: "Vacant" }
      : {
          _tag: "Active",
          pairId: row.pairId,
          members: [
            { user: row.firstUser, presence: row.firstPresence },
            { user: row.secondUser, presence: row.secondPresence },
          ],
          lastSeq: row.lastSeq,
          streak: {
            days: row.streakDays,
            best: row.streakBest,
            ...(row.streakLastDay === null ? {} : { lastDay: row.streakLastDay }),
            ...(row.streakRestoredOn === null ? {} : { restoredOn: row.streakRestoredOn }),
          },
          ...(row.lastReactionRev === null ? {} : { lastReactionRev: row.lastReactionRev }),
          inks,
          items,
          wishlist,
          layout: layout.map(({ itemId, surface, u, v, quarterTurns }) => ({
            item: itemId,
            surface,
            u,
            v,
            quarterTurns,
          })),
          layoutLog: layoutIds,
          bonuses,
          // In the members' order, as the room keeps them.
          moods: [row.firstUser, row.secondUser].flatMap((user) =>
            moods.filter((checkIn) => checkIn.user === user),
          ),
          ...(row.giftDay === null ? {} : { giftDay: row.giftDay }),
          welcomed: row.welcomed,
          wallet: walletFrom(walletRow),
          ...catFrom(catRow),
        },
  );

const roomValues = (state: ActiveRoom): typeof room.$inferInsert => {
  const [first, second] = state.members;
  return {
    id: 1,
    pairId: state.pairId,
    firstUser: first.user,
    firstPresence: first.presence,
    secondUser: second.user,
    secondPresence: second.presence,
    lastSeq: state.lastSeq,
    streakDays: state.streak.days,
    streakBest: state.streak.best,
    streakLastDay: state.streak.lastDay ?? null,
    streakRestoredOn: state.streak.restoredOn ?? null,
    lastReactionRev: state.lastReactionRev ?? null,
    giftDay: state.giftDay ?? null,
    welcomed: state.welcomed,
  };
};

/**
 * A storage failure is a defect: the state is unknown, and the command lock prevents half-writes.
 */
export const SqliteRoomStore = Layer.effect(
  RoomStore,
  Effect.gen(function* () {
    const db = yield* RoomDb;

    return {
      load: Effect.all([
        db.select().from(room),
        db.select().from(cat),
        db.select().from(ownedInk).orderBy(asc(ownedInk.position)),
        db.select().from(ownedItem).orderBy(asc(ownedItem.position)),
        db.select().from(wish).orderBy(asc(wish.position)),
        db.select().from(wallet),
        db.select().from(claimedBonus).orderBy(asc(claimedBonus.position)),
        db.select().from(mood),
        db.select().from(placement).orderBy(asc(placement.position)),
        db.select().from(layoutLog).orderBy(asc(layoutLog.position)),
      ]).pipe(
        Effect.map(
          ([[row], [catRow], inks, items, wishes, [walletRow], bonuses, moods, placed, logged]) =>
            roomFrom(
              row,
              catRow,
              inks.map(({ inkId }) => inkId),
              items.map(({ itemId }) => itemId),
              wishes.map(({ itemId }) => itemId),
              walletRow,
              bonuses.map(({ collectionId }) => collectionId),
              moodsFrom(moods),
              placed,
              logged.map(({ changeId }) => changeId),
            ),
        ),
        Effect.orDie,
      ),
      commit: (
        state: ActiveRoom,
        notes: ReadonlyArray<AppendedNote>,
        catEntries: ReadonlyArray<CatEntry>,
        items: ReadonlyArray<ActivityRow>,
        coins: ReadonlyArray<CoinEntry>,
        reactions: ReadonlyArray<NoteReaction>,
        listWrites: ReadonlyArray<ListWrite>,
        riddleWrites: ReadonlyArray<RiddleWrite>,
      ) =>
        db
          .transaction((tx) =>
            Effect.gen(function* () {
              const values = roomValues(state);
              yield* tx
                .insert(room)
                .values(values)
                .onConflictDoUpdate({ target: room.id, set: values });
              // Inks are only ever added, so the ones already stored keep their place.
              for (const [position, inkId] of state.inks.entries()) {
                yield* tx.insert(ownedInk).values({ inkId, position }).onConflictDoNothing();
              }
              for (const [position, itemId] of state.items.entries()) {
                yield* tx.insert(ownedItem).values({ itemId, position }).onConflictDoNothing();
              }
              // Bonuses are only ever added, like the inks.
              for (const [position, collectionId] of state.bonuses.entries()) {
                yield* tx
                  .insert(claimedBonus)
                  .values({ collectionId, position })
                  .onConflictDoNothing();
              }
              // A row this code could not read stays: only a member's own check-in replaces it.
              for (const checkIn of state.moods) {
                const values = {
                  user: checkIn.user,
                  mood: checkIn.mood,
                  note: checkIn.note ?? null,
                  at: checkIn.at,
                };
                yield* tx
                  .insert(mood)
                  .values(values)
                  .onConflictDoUpdate({ target: mood.user, set: values });
              }
              yield* tx.delete(placement);
              for (const [position, spot] of state.layout.entries()) {
                yield* tx.insert(placement).values({
                  itemId: spot.item,
                  surface: spot.surface,
                  u: spot.u,
                  v: spot.v,
                  quarterTurns: spot.quarterTurns,
                  position,
                });
              }
              yield* tx.delete(layoutLog);
              for (const [position, changeId] of state.layoutLog.entries()) {
                yield* tx.insert(layoutLog).values({ changeId, position });
              }
              yield* tx.delete(wish);
              for (const [position, itemId] of state.wishlist.entries()) {
                yield* tx.insert(wish).values({ itemId, position });
              }
              const purse = walletValues(state);
              yield* tx
                .insert(wallet)
                .values(purse)
                .onConflictDoUpdate({ target: wallet.id, set: purse });
              for (const entry of coins) yield* tx.insert(coinEntry).values(entry);
              for (const { entry, key } of notes) {
                yield* tx.insert(note).values({
                  seq: entry.seq,
                  body: encodeNote(entry.note),
                  author: entry.note.author,
                  idempotencyKey: key,
                });
              }
              const catRow = catValues(state);
              if (catRow !== undefined) {
                yield* tx
                  .insert(cat)
                  .values(catRow)
                  .onConflictDoUpdate({ target: cat.id, set: catRow });
              }
              for (const entry of catEntries) {
                yield* tx.insert(catEntry).values({
                  seq: entry.seq,
                  id: entry.id,
                  by: entry.by,
                  at: entry.at,
                  body: encodeCatEvent(entry.event),
                });
              }
              for (const r of reactions) {
                const values = {
                  noteId: r.note,
                  by: r.by,
                  reaction: r.reaction ?? null,
                  at: r.at,
                  rev: r.rev,
                };
                yield* tx
                  .insert(reaction)
                  .values(values)
                  .onConflictDoUpdate({ target: [reaction.noteId, reaction.by], set: values });
              }
              for (const item of items) {
                const values = activityValues(item);
                yield* tx
                  .insert(activity)
                  .values(values)
                  .onConflictDoUpdate({ target: activity.id, set: values });
              }
              for (const write of listWrites) {
                const id = write._tag === "Put" ? write.list.id : write.list;
                yield* tx.delete(listItems).where(eq(listItems.listId, id));
                if (write._tag === "Drop") {
                  yield* tx.delete(lists).where(eq(lists.id, id));
                } else {
                  const { kind, title, icon, items: listed } = write.list;
                  const tile = { kind, title, iconSymbol: icon.symbol, iconTint: icon.tint };
                  // A new list goes last; one already stored keeps its place.
                  const [last] = yield* tx.select({ at: max(lists.position) }).from(lists);
                  yield* tx
                    .insert(lists)
                    .values({ id, position: (last?.at ?? -1) + 1, ...tile })
                    .onConflictDoUpdate({ target: lists.id, set: tile });
                  for (const [position, item] of listed.entries()) {
                    yield* tx.insert(listItems).values(listItemValues(id, position, item));
                  }
                }
                yield* tx
                  .insert(listKeys)
                  .values({ key: write.key, at: write.at })
                  .onConflictDoNothing();
              }
              for (const write of riddleWrites) yield* writeRiddle(tx, write);
              if (listWrites.length > 0) {
                const [newest] = yield* tx.select({ at: max(listKeys.at) }).from(listKeys);
                const cutoff = (newest?.at ?? 0) - listKeyRetentionMillis;
                yield* tx.delete(listKeys).where(lt(listKeys.at, cutoff));
              }
              if (items.length > 0) {
                // Kept for 30 days behind the newest item: the room has no clock of its own.
                const [newest] = yield* tx.select({ at: max(activity.at) }).from(activity);
                const cutoff = (newest?.at ?? 0) - activityRetentionMillis;
                yield* tx.delete(activity).where(lt(activity.at, cutoff));
              }
            }),
          )
          .pipe(Effect.orDie),
      lists: Effect.all([
        db.select().from(lists).orderBy(asc(lists.position)),
        db.select().from(listItems).orderBy(asc(listItems.listId), asc(listItems.position)),
      ]).pipe(
        Effect.map(([rows, items]) => listsFrom(rows, items)),
        Effect.orDie,
      ),
      listById: (id: ListId) =>
        Effect.all([
          db.select().from(lists).where(eq(lists.id, id)),
          db
            .select()
            .from(listItems)
            .where(eq(listItems.listId, id))
            .orderBy(asc(listItems.position)),
        ]).pipe(
          Effect.map(([rows, items]) => Option.fromNullishOr(listsFrom(rows, items)[0])),
          Effect.orDie,
        ),
      listKeyUsed: (key: IdempotencyKey) =>
        db
          .select({ key: listKeys.key })
          .from(listKeys)
          .where(eq(listKeys.key, key))
          .pipe(
            Effect.map((rows) => rows.length > 0),
            Effect.orDie,
          ),
      forgetLists: db
        .transaction((tx) =>
          Effect.gen(function* () {
            yield* tx.delete(listItems);
            yield* tx.delete(lists);
            yield* tx.delete(listKeys);
          }),
        )
        .pipe(Effect.asVoid, Effect.orDie),
      noteByKey: (author: UserId, key: IdempotencyKey) =>
        db
          .select()
          .from(note)
          .where(and(eq(note.author, author), eq(note.idempotencyKey, key)))
          .pipe(
            Effect.map(([row]) => {
              const decoded = row === undefined ? Option.none() : decodeNoteOption(row.body);
              return Option.map(decoded, (stored) => ({ seq: row?.seq ?? 0, note: stored }));
            }),
            Effect.orDie,
          ),
      // Notes have no id column: the id is in the body, and a room holds few enough to scan.
      noteById: (id: NoteId) =>
        db
          .select()
          .from(note)
          .where(sql`json_extract(${note.body}, '$.id') = ${id}`)
          .pipe(
            Effect.map(([row]) => {
              const decoded = row === undefined ? Option.none() : decodeNoteOption(row.body);
              return Option.map(decoded, (stored) => ({ seq: row?.seq ?? 0, note: stored }));
            }),
            Effect.orDie,
          ),
      reactionOf: (noteId: NoteId, by: UserId) =>
        db
          .select()
          .from(reaction)
          .where(and(eq(reaction.noteId, noteId), eq(reaction.by, by)))
          .pipe(
            Effect.map((rows) => Option.fromNullishOr(reactionsFrom(rows)[0])),
            Effect.orDie,
          ),
      reactionsAfter: (afterRev: number, limit: number) =>
        db
          .select()
          .from(reaction)
          .where(gt(reaction.rev, afterRev))
          .orderBy(asc(reaction.rev))
          .limit(pageSize(limit))
          .pipe(Effect.map(reactionsFrom), Effect.orDie),
      forgetReactions: db.delete(reaction).pipe(Effect.asVoid, Effect.orDie),
      forgetMoods: db.delete(mood).pipe(Effect.asVoid, Effect.orDie),
      notesAfter: (afterSeq: number, limit: number) =>
        Effect.gen(function* () {
          const rows = yield* db
            .select()
            .from(note)
            .where(gt(note.seq, afterSeq))
            .orderBy(asc(note.seq))
            .limit(pageSize(limit));
          const page: SequencedNote[] = [];
          for (const { seq, body } of rows) {
            const decoded = decodeNoteOption(body);
            // A body this code cannot read must not block the room. Clients resume by `seq`, so
            // the gap is harmless; the log line carries the seq and nothing from the body.
            if (Option.isNone(decoded)) yield* Effect.logWarning("note body unreadable", { seq });
            else page.push({ seq, note: decoded.value });
          }
          return page;
        }).pipe(Effect.orDie),
      catEntryById: (id: IdempotencyKey) =>
        db
          .select()
          .from(catEntry)
          .where(eq(catEntry.id, id))
          .pipe(
            Effect.map(([row]) => (row === undefined ? Option.none() : catEntryFrom(row))),
            Effect.orDie,
          ),
      coinEntryById: (id: CoinEntryId) =>
        db
          .select()
          .from(coinEntry)
          .where(eq(coinEntry.id, id))
          .pipe(
            Effect.map((rows) => Option.fromNullishOr(coinEntriesFrom(rows)[0])),
            Effect.orDie,
          ),
      coinEntriesAfter: (after: CoinEntryId | undefined, limit: number) =>
        Effect.gen(function* () {
          const [mark] =
            after === undefined
              ? []
              : yield* db
                  .select({ seq: coinEntry.seq })
                  .from(coinEntry)
                  .where(eq(coinEntry.id, after));
          const rows = yield* db
            .select()
            .from(coinEntry)
            .where(gt(coinEntry.seq, mark?.seq ?? 0))
            .orderBy(asc(coinEntry.seq))
            .limit(pageSize(limit));
          return coinEntriesFrom(rows);
        }).pipe(Effect.orDie),
      catEntriesAfter: (afterSeq: number, limit: number) =>
        db
          .select()
          .from(catEntry)
          .where(gt(catEntry.seq, afterSeq))
          .orderBy(asc(catEntry.seq))
          .limit(pageSize(limit))
          .pipe(Effect.map(catEntriesFrom), Effect.orDie),
      catEntriesSince: (since: EpochMillis) =>
        db
          .select()
          .from(catEntry)
          .where(gte(catEntry.at, since))
          .orderBy(asc(catEntry.seq))
          .pipe(Effect.map(catEntriesFrom), Effect.orDie),
      activityBefore: (before: ActivityCursor | undefined, limit: number) =>
        db
          .select()
          .from(activity)
          .where(before === undefined ? undefined : lt(activity.sortKey, before))
          .orderBy(desc(activity.sortKey))
          .limit(pageSize(limit))
          .pipe(
            Effect.map((rows) => rows.flatMap((row) => Option.toArray(activityFrom(row)))),
            Effect.orDie,
          ),
      // The caller's own items are never theirs to read.
      unreadCount: (user: UserId, mark: ActivityCursor | undefined) =>
        db
          .select({ n: count() })
          .from(activity)
          .where(
            and(
              mark === undefined ? undefined : gt(activity.sortKey, mark),
              or(isNull(activity.doerUser), ne(activity.doerUser, user)),
            ),
          )
          .pipe(
            Effect.map(([row]) => row?.n ?? 0),
            Effect.orDie,
          ),
      readMark: (user: UserId) =>
        db
          .select()
          .from(activityRead)
          .where(eq(activityRead.user, user))
          .pipe(
            Effect.map(([row]) =>
              row === undefined ? Option.none() : decodeCursorOption(row.upTo),
            ),
            Effect.orDie,
          ),
      saveReadMark: (user: UserId, mark: ActivityCursor) =>
        db
          .insert(activityRead)
          .values({ user, upTo: mark })
          .onConflictDoUpdate({ target: activityRead.user, set: { upTo: mark } })
          .pipe(Effect.asVoid, Effect.orDie),
      forgetActivity: db
        .transaction((tx) =>
          Effect.gen(function* () {
            yield* tx.delete(activity);
            yield* tx.delete(activityRead);
          }),
        )
        .pipe(Effect.asVoid, Effect.orDie),
      forgetCat: db
        .transaction((tx) =>
          Effect.gen(function* () {
            yield* tx.delete(catEntry);
            yield* tx.delete(cat);
          }),
        )
        .pipe(Effect.asVoid, Effect.orDie),
      // Notes stored before `author` existed have it only in the body.
      forgetAuthor: (author: UserId) =>
        Effect.gen(function* () {
          const rows = yield* db
            .delete(note)
            .where(
              or(
                eq(note.author, author),
                and(isNull(note.author), sql`json_extract(${note.body}, '$.author') = ${author}`),
              ),
            )
            .returning({ seq: note.seq, body: note.body });
          const forgotten: SequencedNote[] = [];
          for (const { seq, body } of rows.toSorted((a, b) => a.seq - b.seq)) {
            const decoded = decodeNoteOption(body);
            if (Option.isSome(decoded)) forgotten.push({ seq, note: decoded.value });
          }
          return forgotten;
        }).pipe(Effect.orDie),
    };
  }),
);
