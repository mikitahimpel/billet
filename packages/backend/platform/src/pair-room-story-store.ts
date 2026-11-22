import { Effect, Layer, Option, Schema } from "effect";
import { StoryRow, StoryStore } from "@billet/backend-pair-room/story";
import { RoomDb } from "./pair-room-sqlite-store.ts";
import { storyMarks } from "./room-schema.ts";

const decodeRow = Schema.decodeUnknownOption(StoryRow);

/** `StoryStore` on the room's own SQLite. A row this code cannot read is left out. */
export const SqliteStoryStore = Layer.effect(
  StoryStore,
  Effect.gen(function* () {
    const db = yield* RoomDb;
    return StoryStore.of({
      all: db
        .select()
        .from(storyMarks)
        .pipe(
          Effect.map((rows) => rows.flatMap((row) => Option.toArray(decodeRow(row)))),
          Effect.orDie,
        ),
      put: (row) =>
        db.insert(storyMarks).values(row).onConflictDoNothing().pipe(Effect.asVoid, Effect.orDie),
      forget: db.delete(storyMarks).pipe(Effect.asVoid, Effect.orDie),
    });
  }),
);
