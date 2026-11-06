import { and, asc, desc, eq, isNotNull, isNull } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { RiddleStore } from "@billet/backend-pair-room/riddle";
import { noRiddleSeries, RiddleGuessRow, RiddleRow } from "@billet/backend-pair-room/riddle-rules";
import { RoomDb } from "./pair-room-sqlite-store.ts";
import { riddleGuesses, riddleSeries, riddles } from "./room-schema.ts";

const RiddleJson = Schema.fromJsonString(RiddleRow);
const decodeRiddle = Schema.decodeOption(RiddleJson);
const decodeGuess = Schema.decodeUnknownOption(RiddleGuessRow);

/** A row this code cannot read, such as one a newer build wrote, is left out. */
const riddlesFrom = (rows: ReadonlyArray<{ readonly body: string }>) =>
  rows.flatMap((row) => Option.toArray(decodeRiddle(row.body)));

/** `RiddleStore` on the room's own SQLite, reading what the room's commit wrote. */
export const SqliteRiddleStore = Layer.effect(
  RiddleStore,
  Effect.gen(function* () {
    const db = yield* RoomDb;
    return RiddleStore.of({
      byId: (id) =>
        db
          .select()
          .from(riddles)
          .where(eq(riddles.id, id))
          .pipe(
            Effect.map((rows) => Option.fromNullishOr(riddlesFrom(rows)[0])),
            Effect.orDie,
          ),
      open: db
        .select()
        .from(riddles)
        .where(isNull(riddles.endedAt))
        .pipe(
          // `at` lives in the body, so the rows are put oldest first after decoding.
          Effect.map((rows) => riddlesFrom(rows).toSorted((a, b) => a.at - b.at)),
          Effect.orDie,
        ),
      ended: (limit) =>
        db
          .select()
          .from(riddles)
          .where(isNotNull(riddles.endedAt))
          .orderBy(desc(riddles.endedAt), asc(riddles.id))
          .limit(Math.max(0, limit))
          .pipe(Effect.map(riddlesFrom), Effect.orDie),
      guess: (riddle, key) =>
        db
          .select()
          .from(riddleGuesses)
          .where(and(eq(riddleGuesses.riddle, riddle), eq(riddleGuesses.key, key)))
          .pipe(
            Effect.map((rows) => Option.flatMap(Option.fromNullishOr(rows[0]), decodeGuess)),
            Effect.orDie,
          ),
      series: db
        .select()
        .from(riddleSeries)
        .pipe(
          Effect.map(([row]) =>
            row === undefined ? noRiddleSeries : { series: row.series, best: row.best },
          ),
          Effect.orDie,
        ),
      forget: db
        .transaction((tx) =>
          Effect.gen(function* () {
            yield* tx.delete(riddleGuesses);
            yield* tx.delete(riddles);
            yield* tx.delete(riddleSeries);
          }),
        )
        .pipe(Effect.asVoid, Effect.orDie),
    });
  }),
);
