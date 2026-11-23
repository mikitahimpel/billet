import { Schema } from "effect";
import {
  Routine,
  RoutineSteps,
  SchoolTrick,
  TrickId,
  TrickStars,
} from "@billet/contracts-domain/school";

/** What the pair's cat knows, and the last routine each of the two sent. */
export const SchoolResponse = Schema.Struct({
  tricks: Schema.Array(SchoolTrick),
  mine: Schema.optionalKey(Routine),
  partner: Schema.optionalKey(Routine),
});
export type SchoolResponse = typeof SchoolResponse.Type;

/**
 * `POST /v1/school/lessons`: a lesson passed. `stars` is the star it earns: one more than the
 * trick has. A star the trick already has changes nothing; a skipped star is refused.
 */
export const LessonRequest = Schema.Struct({ trick: TrickId, stars: TrickStars });
export type LessonRequest = typeof LessonRequest.Type;

/** `POST /v1/school/routines`: replaces the caller's last routine. Every trick in it is known. */
export const RoutineRequest = Schema.Struct({ steps: RoutineSteps });
export type RoutineRequest = typeof RoutineRequest.Type;
