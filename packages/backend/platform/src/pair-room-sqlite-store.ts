import { Context, Effect, Layer, Option, Schema } from "effect";
import { Note } from "@billet/contracts-domain/note";
import {
  RoomState,
  type ActiveRoom,
  type SequencedNote,
} from "@billet/backend-pair-room/room-state";
import { RoomStore } from "@billet/backend-pair-room/room-store";

/** The storage of the Durable Object that owns this runtime. */
export class RoomStorage extends Context.Service<RoomStorage, DurableObjectStorage>()(
  "@billet/backend-platform/RoomStorage",
) {}

/**
 * Applied in order, each exactly once. A Durable Object cannot be rebuilt, so ship changes by
 * appending here and never by editing a step that has already run.
 */
const migrations: ReadonlyArray<string> = [
  `CREATE TABLE room (
     id INTEGER PRIMARY KEY CHECK (id = 1),
     pair_id TEXT NOT NULL,
     first_user TEXT NOT NULL,
     first_presence TEXT NOT NULL,
     second_user TEXT NOT NULL,
     second_presence TEXT NOT NULL,
     last_seq INTEGER NOT NULL,
     streak_days INTEGER NOT NULL
   );
   CREATE TABLE note (
     seq INTEGER PRIMARY KEY,
     body TEXT NOT NULL
   );`,
];

const migrate = (storage: DurableObjectStorage): void => {
  storage.transactionSync(() => {
    storage.sql.exec("CREATE TABLE IF NOT EXISTS migration (version INTEGER PRIMARY KEY)");
    const { applied } = storage.sql
      .exec<{ applied: number }>("SELECT count(*) AS applied FROM migration")
      .one();
    migrations.slice(applied).forEach((sql, index) => {
      storage.sql.exec(sql);
      storage.sql.exec("INSERT INTO migration (version) VALUES (?)", applied + index + 1);
    });
  });
};

const NoteJson = Schema.fromJsonString(Note);
const encodeNote = Schema.encodeSync(NoteJson);
const decodeNoteOption = Schema.decodeOption(NoteJson);

/** The most notes one call returns. A smaller, zero or negative `limit` is honoured, never unbounded. */
export const MAX_NOTES_PER_PAGE = 100;
const pageSize = (limit: number): number =>
  Math.max(0, Math.min(Math.trunc(limit), MAX_NOTES_PER_PAGE));
const decodeRoom = Schema.decodeUnknownSync(RoomState);

type RoomRow = {
  pair_id: string;
  first_user: string;
  first_presence: string;
  second_user: string;
  second_presence: string;
  last_seq: number;
  streak_days: number;
};

const roomFrom = (row: RoomRow | undefined): RoomState =>
  decodeRoom(
    row === undefined
      ? { _tag: "Vacant" }
      : {
          _tag: "Active",
          pairId: row.pair_id,
          members: [
            { user: row.first_user, presence: row.first_presence },
            { user: row.second_user, presence: row.second_presence },
          ],
          lastSeq: row.last_seq,
          streakDays: row.streak_days,
        },
  );

const saveRoom = (sql: SqlStorage, room: ActiveRoom): void => {
  const [first, second] = room.members;
  sql.exec(
    `INSERT OR REPLACE INTO room
       (id, pair_id, first_user, first_presence, second_user, second_presence, last_seq, streak_days)
     VALUES (1, ?, ?, ?, ?, ?, ?, ?)`,
    room.pairId,
    first.user,
    first.presence,
    second.user,
    second.presence,
    room.lastSeq,
    room.streakDays,
  );
};

/** `RoomStore` on the object's own SQLite database. */
export const SqliteRoomStore = Layer.effect(
  RoomStore,
  Effect.gen(function* () {
    const storage = yield* RoomStorage;
    migrate(storage);
    const { sql } = storage;

    return {
      load: Effect.sync(() => roomFrom(sql.exec<RoomRow>("SELECT * FROM room").toArray()[0])),
      commit: (room: ActiveRoom, notes: ReadonlyArray<SequencedNote>) =>
        Effect.sync(() => {
          storage.transactionSync(() => {
            saveRoom(sql, room);
            for (const { seq, note } of notes) {
              sql.exec("INSERT INTO note (seq, body) VALUES (?, ?)", seq, encodeNote(note));
            }
          });
        }),
      notesAfter: (afterSeq: number, limit: number) =>
        Effect.gen(function* () {
          const rows = sql
            .exec<{ seq: number; body: string }>(
              "SELECT seq, body FROM note WHERE seq > ? ORDER BY seq LIMIT ?",
              afterSeq,
              pageSize(limit),
            )
            .toArray();
          const page: SequencedNote[] = [];
          for (const { seq, body } of rows) {
            const note = decodeNoteOption(body);
            // A body this code cannot read must not block the room. Clients resume by `seq`, so
            // the gap is harmless; the log line carries the seq and nothing from the body.
            if (Option.isNone(note)) yield* Effect.logWarning("note body unreadable", { seq });
            else page.push({ seq, note: note.value });
          }
          return page;
        }),
    };
  }),
);
