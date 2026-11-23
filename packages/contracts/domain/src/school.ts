import { Schema } from "effect";
import { EpochMillis, UserId } from "./ids.ts";

/** A trick the app ships: lowercase words joined by hyphens, such as `high-five`. */
export const TrickId = Schema.String.check(
  Schema.isPattern(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/),
  Schema.isMaxLength(24),
).pipe(Schema.brand("TrickId"));
export type TrickId = typeof TrickId.Type;

export const trickMaxStars = 3;

/** How well the cat knows a trick. One star is added by each lesson passed. */
export const TrickStars = Schema.Int.check(
  Schema.isBetween({ minimum: 1, maximum: trickMaxStars }),
);
export type TrickStars = typeof TrickStars.Type;

/** A trick the pair's cat knows. `by` taught its first star; `at` is its latest star. */
export const SchoolTrick = Schema.Struct({
  trick: TrickId,
  stars: TrickStars,
  by: UserId,
  at: EpochMillis,
});
export type SchoolTrick = typeof SchoolTrick.Type;

export const routineMinSteps = 3;
export const routineMaxSteps = 5;

/** One trick asked for in a routine, and whether the cat did it or did something else. */
export const RoutineStep = Schema.Struct({ trick: TrickId, landed: Schema.Boolean });
export type RoutineStep = typeof RoutineStep.Type;

export const RoutineSteps = Schema.Array(RoutineStep).check(
  Schema.isMinLength(routineMinSteps),
  Schema.isMaxLength(routineMaxSteps),
);
export type RoutineSteps = typeof RoutineSteps.Type;

/** One take of a routine as it went, so the partner's room can play the same take. */
export const Routine = Schema.Struct({ steps: RoutineSteps, at: EpochMillis });
export type Routine = typeof Routine.Type;
