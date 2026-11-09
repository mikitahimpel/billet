import { Schema } from "effect";
import { UtcOffsetSeconds } from "@billet/contracts-domain/cat";
import { EpochMillis } from "@billet/contracts-domain/ids";
import { LoveStreak } from "@billet/contracts-domain/streak";

/** `GET /v1/streak`, and the answer to a day or a restore: the pair's streak as the room has it. */
export const StreakResponse = Schema.Struct({ streak: LoveStreak });
export type StreakResponse = typeof StreakResponse.Type;

/** `at` is phone time: counted at most a day back, never past the room's clock. */
export const RecordStreakDayRequest = Schema.Struct({
  at: EpochMillis,
  utcOffsetSeconds: UtcOffsetSeconds,
});
export type RecordStreakDayRequest = typeof RecordStreakDayRequest.Type;

/** `POST /v1/streak/restore`: brings back a streak that went out yesterday, once a month a pair. */
export const RestoreStreakRequest = Schema.Struct({ utcOffsetSeconds: UtcOffsetSeconds });
export type RestoreStreakRequest = typeof RestoreStreakRequest.Type;
