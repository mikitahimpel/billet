import { Schema } from "effect";
import { EpochMillis } from "@billet/contracts-domain/ids";

/** What a `room` row holds. A test fails if the table's columns differ. */
export const StoredRoom = Schema.Struct({
  id: Schema.Int,
  pairId: Schema.String,
  firstUser: Schema.String,
  firstPresence: Schema.String,
  secondUser: Schema.String,
  secondPresence: Schema.String,
  lastSeq: Schema.Int,
  streakDays: Schema.Int,
});

/** What a `note` row holds. */
export const StoredNote = Schema.Struct({ seq: Schema.Int, body: Schema.String });

/** A row with every column shape a table can have, for tests that check the check. */
export const SampleRow = Schema.Struct({ id: Schema.String, createdAt: EpochMillis });
