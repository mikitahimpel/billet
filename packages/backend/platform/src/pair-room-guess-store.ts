import { asc, eq, sql } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import {
  GuessAnswerRow,
  GuessRoundRow,
  GuessStore,
  GuessWeekRow,
} from "@billet/backend-pair-room/guess";
import { RoomDb } from "./pair-room-sqlite-store.ts";
import { guessAnswers, guessRounds, guessWeeks } from "./room-schema.ts";

const decodeRound = Schema.decodeUnknownOption(GuessRoundRow);
const decodeAnswer = Schema.decodeUnknownOption(GuessAnswerRow);
const decodeWeek = Schema.decodeUnknownOption(GuessWeekRow);

const parsed = (json: string): unknown => {
  try {
    return JSON.parse(json);
  } catch {
    return undefined;
  }
};

/** A row this code cannot read, such as one a newer build wrote, is left out. */
const roundFrom = (row: typeof guessRounds.$inferSelect) =>
  decodeRound({ day: row.day, subject: row.subject, questions: parsed(row.questions) });

/** `GuessStore` on the room's own SQLite. */
export const SqliteGuessStore = Layer.effect(
  GuessStore,
  Effect.gen(function* () {
    const db = yield* RoomDb;
    return GuessStore.of({
      round: (day) =>
        db
          .select()
          .from(guessRounds)
          .where(eq(guessRounds.day, day))
          .pipe(
            Effect.map((rows) => Option.flatMap(Option.fromNullishOr(rows[0]), roundFrom)),
            Effect.orDie,
          ),
      rounds: db
        .select()
        .from(guessRounds)
        .orderBy(asc(guessRounds.day))
        .pipe(
          Effect.map((rows) => rows.flatMap((row) => Option.toArray(roundFrom(row)))),
          Effect.orDie,
        ),
      startRound: (round) =>
        db
          .insert(guessRounds)
          .values({
            day: round.day,
            subject: round.subject,
            questions: JSON.stringify(round.questions),
          })
          .onConflictDoNothing()
          .pipe(Effect.asVoid, Effect.orDie),
      answers: (day) =>
        db
          .select()
          .from(guessAnswers)
          .where(eq(guessAnswers.day, day))
          .orderBy(asc(guessAnswers.at))
          .pipe(
            Effect.map((rows) => rows.flatMap((row) => Option.toArray(decodeAnswer(row)))),
            Effect.orDie,
          ),
      weeks: db
        .select()
        .from(guessWeeks)
        .pipe(
          Effect.map((rows) => rows.flatMap((row) => Option.toArray(decodeWeek(row)))),
          Effect.orDie,
        ),
      answer: (row, score) =>
        db
          .transaction((tx) =>
            Effect.gen(function* () {
              yield* tx.insert(guessAnswers).values(row);
              if (score === undefined) return;
              yield* tx
                .insert(guessWeeks)
                .values(score)
                .onConflictDoUpdate({
                  target: [guessWeeks.week, guessWeeks.member],
                  set: { points: sql`${guessWeeks.points} + ${score.points}` },
                });
            }),
          )
          .pipe(Effect.asVoid, Effect.orDie),
      forget: db
        .transaction((tx) =>
          Effect.gen(function* () {
            yield* tx.delete(guessAnswers);
            yield* tx.delete(guessRounds);
            yield* tx.delete(guessWeeks);
          }),
        )
        .pipe(Effect.asVoid, Effect.orDie),
    });
  }),
);
