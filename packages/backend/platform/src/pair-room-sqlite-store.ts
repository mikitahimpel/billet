import { asc, gt } from "drizzle-orm";
import { Context, Effect, Layer, Option, Schema } from "effect";
import { Note } from "@billet/contracts-domain/note";
import {
  RoomState,
  type ActiveRoom,
  type SequencedNote,
} from "@billet/backend-pair-room/room-state";
import { RoomStore } from "@billet/backend-pair-room/room-store";
import type { RoomDatabase } from "./room-database.ts";
import { note, room } from "./room-schema.ts";

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

const roomFrom = (row: RoomRow | undefined): RoomState =>
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
      load: db
        .select()
        .from(room)
        .pipe(
          Effect.map(([row]) => roomFrom(row)),
          Effect.orDie,
        ),
      commit: (state: ActiveRoom, notes: ReadonlyArray<SequencedNote>) =>
        db
          .transaction((tx) =>
            Effect.gen(function* () {
              const values = roomValues(state);
              yield* tx
                .insert(room)
                .values(values)
                .onConflictDoUpdate({ target: room.id, set: values });
              for (const entry of notes) {
                yield* tx.insert(note).values({ seq: entry.seq, body: encodeNote(entry.note) });
              }
            }),
          )
          .pipe(Effect.orDie),
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
    };
  }),
);
