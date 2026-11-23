import { Effect, Layer, Option, Schema } from "effect";
import { RoutineRow, SchoolStore } from "@billet/backend-pair-room/school";
import { RoutineSteps, SchoolTrick } from "@billet/contracts-domain/school";
import { RoomDb } from "./pair-room-sqlite-store.ts";
import { schoolRoutines, schoolTricks } from "./room-schema.ts";

const decodeTrick = Schema.decodeUnknownOption(SchoolTrick);
const decodeRoutine = Schema.decodeUnknownOption(
  Schema.Struct({ ...RoutineRow.fields, steps: Schema.fromJsonString(RoutineSteps) }),
);
const encodeSteps = Schema.encodeSync(Schema.fromJsonString(RoutineSteps));

/** `SchoolStore` on the room's own SQLite. A row this code cannot read is left out. */
export const SqliteSchoolStore = Layer.effect(
  SchoolStore,
  Effect.gen(function* () {
    const db = yield* RoomDb;
    return SchoolStore.of({
      all: Effect.all({
        tricks: db
          .select()
          .from(schoolTricks)
          .pipe(Effect.map((rows) => rows.flatMap((row) => Option.toArray(decodeTrick(row))))),
        routines: db
          .select()
          .from(schoolRoutines)
          .pipe(Effect.map((rows) => rows.flatMap((row) => Option.toArray(decodeRoutine(row))))),
      }).pipe(Effect.orDie),
      putTrick: ({ trick, stars, by, at }) =>
        db
          .insert(schoolTricks)
          .values({ trick, stars, by, at })
          .onConflictDoUpdate({ target: schoolTricks.trick, set: { stars, at } })
          .pipe(Effect.asVoid, Effect.orDie),
      putRoutine: ({ member, steps, at }) => {
        const json = encodeSteps(steps);
        return db
          .insert(schoolRoutines)
          .values({ member, steps: json, at })
          .onConflictDoUpdate({ target: schoolRoutines.member, set: { steps: json, at } })
          .pipe(Effect.asVoid, Effect.orDie);
      },
      forget: Effect.all([db.delete(schoolTricks), db.delete(schoolRoutines)]).pipe(
        Effect.asVoid,
        Effect.orDie,
      ),
    });
  }),
);
