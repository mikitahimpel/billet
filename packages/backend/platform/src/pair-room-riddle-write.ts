import { Effect, Schema } from "effect";
import { endedAt, RiddleRow, type RiddleWrite } from "@billet/backend-pair-room/riddle-rules";
import type { RoomDatabase } from "./room-database.ts";
import { riddleGuesses, riddleSeries, riddles } from "./room-schema.ts";

const encodeRiddle = Schema.encodeSync(Schema.fromJsonString(RiddleRow));

/** Stores one riddle change. The room's commit calls it inside its transaction. */
export const writeRiddle = (
  tx: Pick<RoomDatabase, "insert">,
  { riddle, guess, series }: RiddleWrite,
) =>
  Effect.gen(function* () {
    const values = {
      id: riddle.id,
      drawer: riddle.drawer,
      endedAt: endedAt(riddle) ?? null,
      body: encodeRiddle(riddle),
    };
    yield* tx
      .insert(riddles)
      .values(values)
      .onConflictDoUpdate({ target: riddles.id, set: values });
    if (guess !== undefined) yield* tx.insert(riddleGuesses).values(guess);
    if (series !== undefined) {
      const row = { id: 1, ...series };
      yield* tx
        .insert(riddleSeries)
        .values(row)
        .onConflictDoUpdate({ target: riddleSeries.id, set: series });
    }
  });
