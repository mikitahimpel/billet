import { Schema } from "effect";
import { UtcOffsetSeconds } from "@billet/contracts-domain/cat";
import { EpochMillis } from "@billet/contracts-domain/ids";
import { LoveStreak } from "@billet/contracts-domain/streak";

/** `GET /v1/streak`, and the answer to a day or a restore: the pair's streak as the room has it. */
export const StreakResponse = Schema.Struct({ streak: LoveStreak });
export type StreakResponse = typeof StreakResponse.Type;

/**
 * `POST /v1/streak/days`: the caller did something together today. `at` is when it happened on
 * the phone, which may be earlier than the request after a time offline; the room counts it no
 * more than a day back, and never after its own clock. The day is counted `utcOffsetSeconds` from
 * UTC, the caller's clock.
 */
export const RecordStreakDayRequest = Schema.Struct({
  at: EpochMillis,
  utcOffsetSeconds: UtcOffsetSeconds,
});
export type RecordStreakDayRequest = typeof RecordStreakDayRequest.Type;

/** `POST /v1/streak/restore`: brings back a streak that went out yesterday, once a month a pair. */
export const RestoreStreakRequest = Schema.Struct({ utcOffsetSeconds: UtcOffsetSeconds });
export type RestoreStreakRequest = typeof RestoreStreakRequest.Type;
