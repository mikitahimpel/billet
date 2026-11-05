import { and, asc, count, desc, eq, gt, gte, isNull, lt, max, ne, or, sql } from "drizzle-orm";
import { Context, Effect, Layer, Option, Schema } from "effect";
import { ActivityCursor, ActivityEvent, ActivityTarget } from "@billet/contracts-domain/activity";
import { CatEntry, CatEvent } from "@billet/contracts-domain/cat";
import type { EpochMillis, IdempotencyKey, UserId } from "@billet/contracts-domain/ids";
import { Note } from "@billet/contracts-domain/note";
import {
  RoomState,
  type ActiveRoom,
  type SequencedNote,
} from "@billet/backend-pair-room/room-state";
import { ActivityRow, activityRetentionMillis, cursorOf } from "@billet/backend-pair-room/activity";
import { RoomStore, type AppendedNote } from "@billet/backend-pair-room/room-store";
import type { RoomDatabase } from "./room-database.ts";
import { activity, activityRead, cat, catEntry, note, room } from "./room-schema.ts";

/** The Drizzle handle of the Durable Object that owns this runtime, already migrated. */
export class RoomDb extends Context.Service<RoomDb, RoomDatabase>()(
  "@billet/backend-platform/RoomDb",
) {}

const NoteJson = Schema.fromJsonString(Note);
const encodeNote = Schema.encodeSync(NoteJson);
const decodeNoteOption = Schema.decodeOption(NoteJson);

/** The most notes one call returns. A smaller, zero or negative `limit` is honoured, never unbounded. */
export const MAX_NOTES_PER_PAGE = 100;
const pageSize = (limit: number): number =>
  Math.max(0, Math.min(Math.trunc(limit), MAX_NOTES_PER_PAGE));
const decodeRoom = Schema.decodeUnknownSync(RoomState);

type RoomRow = typeof room.$inferSelect;
type CatRow = typeof cat.$inferSelect;
type CatEntryRow = typeof catEntry.$inferSelect;

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

const roomFrom = (row: RoomRow | undefined, catRow: CatRow | undefined): RoomState =>
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
          streakDays: row.streakDays,
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
    streakDays: state.streakDays,
  };
};

/**
 * `RoomStore` on the object's own SQLite database. A storage failure is a defect: the object's
 * state is unknown, and the lock around commands keeps it from being half-written.
 */
export const SqliteRoomStore = Layer.effect(
  RoomStore,
  Effect.gen(function* () {
    const db = yield* RoomDb;

    return {
      load: Effect.all([db.select().from(room), db.select().from(cat)]).pipe(
        Effect.map(([[row], [catRow]]) => roomFrom(row, catRow)),
        Effect.orDie,
      ),
      commit: (
        state: ActiveRoom,
        notes: ReadonlyArray<AppendedNote>,
        catEntries: ReadonlyArray<CatEntry>,
        items: ReadonlyArray<ActivityRow>,
      ) =>
        db
          .transaction((tx) =>
            Effect.gen(function* () {
              const values = roomValues(state);
              yield* tx
                .insert(room)
                .values(values)
                .onConflictDoUpdate({ target: room.id, set: values });
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
              for (const item of items) {
                const values = activityValues(item);
                yield* tx
                  .insert(activity)
                  .values(values)
                  .onConflictDoUpdate({ target: activity.id, set: values });
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
