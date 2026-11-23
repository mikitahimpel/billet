import { Clock, Context, Effect, Layer, Schema, Semaphore } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { RoutineSteps, SchoolTrick } from "@billet/contracts-domain/school";
import { LessonRequest, RoutineRequest, SchoolResponse } from "@billet/contracts-http-api/school";
import { RoomStore } from "./room-store.ts";

/** Tricks one cat may know: far above what the app ships, and a bound on the table. */
export const schoolTricksInAll = 40;

/** One member's last routine, as the room stores it. */
export const RoutineRow = Schema.Struct({ member: UserId, steps: RoutineSteps, at: EpochMillis });
export type RoutineRow = typeof RoutineRow.Type;

export interface SchoolRows {
  readonly tricks: ReadonlyArray<SchoolTrick>;
  readonly routines: ReadonlyArray<RoutineRow>;
}

export type LessonDecision =
  | { readonly _tag: "Keep" }
  | { readonly _tag: "Write"; readonly write: SchoolTrick }
  | { readonly _tag: "Invalid" };

/**
 * Pure. A star is earned one at a time, by either of the two, and never lost; the first teacher
 * stays the trick's teacher. A retry of a star already held changes nothing.
 */
export const decideLesson = (
  tricks: ReadonlyArray<SchoolTrick>,
  by: UserId,
  request: LessonRequest,
  at: EpochMillis,
): LessonDecision => {
  const known = tricks.find((row) => row.trick === request.trick);
  const stars = known?.stars ?? 0;
  if (request.stars <= stars) return { _tag: "Keep" };
  if (request.stars !== stars + 1) return { _tag: "Invalid" };
  if (known === undefined && tricks.length >= schoolTricksInAll) return { _tag: "Invalid" };
  return {
    _tag: "Write",
    write: { trick: request.trick, stars: request.stars, by: known?.by ?? by, at },
  };
};

/** Pure. A routine holds only tricks the cat knows. */
export const routineIsKnown = (tricks: ReadonlyArray<SchoolTrick>, request: RoutineRequest) =>
  request.steps.every((step) => tricks.some((row) => row.trick === step.trick));

/** The school as `caller` sees it. */
export const schoolView = (rows: SchoolRows, caller: UserId): SchoolResponse => {
  const routineOf = (mine: boolean) => {
    const row = rows.routines.find((routine) => (routine.member === caller) === mine);
    return row === undefined ? undefined : { steps: row.steps, at: row.at };
  };
  const mine = routineOf(true);
  const partner = routineOf(false);
  return {
    tricks: rows.tricks.toSorted((a, b) => a.at - b.at),
    ...(mine === undefined ? {} : { mine }),
    ...(partner === undefined ? {} : { partner }),
  };
};

/** The school of one room. Failures are defects, as for `RoomStore`. */
export class SchoolStore extends Context.Service<
  SchoolStore,
  {
    readonly all: Effect.Effect<SchoolRows>;
    /** Replaces the trick's row. */
    readonly putTrick: (row: SchoolTrick) => Effect.Effect<void>;
    /** Replaces the member's routine. */
    readonly putRoutine: (row: RoutineRow) => Effect.Effect<void>;
    /** Deletes everything: the pair is ending. */
    readonly forget: Effect.Effect<void>;
  }
>()("@billet/backend-pair-room/SchoolStore") {}

export const SchoolCommand = Schema.TaggedUnion({
  View: {},
  Lesson: LessonRequest.fields,
  Routine: RoutineRequest.fields,
});
export type SchoolCommand = typeof SchoolCommand.Type;

/** The school after a command, that the room is not open, or that the command breaks a rule. */
export const SchoolResult = Schema.TaggedUnion({
  Done: { view: SchoolResponse },
  Refused: { reason: Schema.Literals(["NotOpen", "Invalid"]) },
});
export type SchoolResult = typeof SchoolResult.Type;

/** Runs school commands against one room: load, decide, store, view. */
export class SchoolRoom extends Context.Service<SchoolRoom>()(
  "@billet/backend-pair-room/SchoolRoom",
  {
    make: Effect.gen(function* () {
      const store = yield* SchoolStore;
      const room = yield* RoomStore;
      const lock = yield* Semaphore.make(1);

      const done = (rows: SchoolRows, by: UserId) =>
        SchoolResult.cases.Done.make({ view: schoolView(rows, by) });
      const invalid = SchoolResult.cases.Refused.make({ reason: "Invalid" });

      const run = (by: UserId, command: SchoolCommand): Effect.Effect<SchoolResult> =>
        Effect.gen(function* () {
          const state = yield* room.load;
          if (state._tag !== "Active" || !state.members.some((member) => member.user === by)) {
            return SchoolResult.cases.Refused.make({ reason: "NotOpen" });
          }
          const rows = yield* store.all;
          const at = yield* Clock.currentTimeMillis;
          switch (command._tag) {
            case "View":
              return done(rows, by);
            case "Lesson": {
              const decision = decideLesson(rows.tricks, by, command, at);
              if (decision._tag === "Keep") return done(rows, by);
              if (decision._tag === "Invalid") return invalid;
              const { write } = decision;
              yield* store.putTrick(write);
              const tricks = [...rows.tricks.filter((row) => row.trick !== write.trick), write];
              return done({ ...rows, tricks }, by);
            }
            case "Routine": {
              if (!routineIsKnown(rows.tricks, command)) return invalid;
              const write: RoutineRow = { member: by, steps: command.steps, at };
              yield* store.putRoutine(write);
              const routines = [...rows.routines.filter((row) => row.member !== by), write];
              return done({ ...rows, routines }, by);
            }
          }
        }).pipe(lock.withPermits(1));

      return { run, forget: store.forget.pipe(lock.withPermits(1)) };
    }),
  },
) {
  static readonly layer = Layer.effect(SchoolRoom, SchoolRoom.make);
}
