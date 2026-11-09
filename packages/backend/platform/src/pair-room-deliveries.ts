import { and, eq } from "drizzle-orm";
import { Effect } from "effect";
import type { DeliveryEntry, DeliveryStatus } from "@billet/backend-pair-room/delivery-ledger";
import type { RoomDatabase } from "./room-database.ts";
import { delivery } from "./room-schema.ts";

const entryFrom = (row: typeof delivery.$inferSelect): DeliveryEntry => ({
  noteId: row.noteId,
  lane: row.lane,
  status: row.status as DeliveryStatus,
  attempts: row.attempts,
  nextAttemptAt: row.nextAttemptAt,
});

/** A storage failure is a defect, like the rest of the room. */
export const deliveriesOf = (db: RoomDatabase) => ({
  find: (noteId: string, lane: string) =>
    db
      .select()
      .from(delivery)
      .where(and(eq(delivery.noteId, noteId), eq(delivery.lane, lane)))
      .pipe(
        Effect.map(([row]) => (row === undefined ? undefined : entryFrom(row))),
        Effect.orDie,
      ),
  all: db
    .select()
    .from(delivery)
    .pipe(
      Effect.map((rows) => rows.map(entryFrom)),
      Effect.orDie,
    ),
  forget: (noteId: string) =>
    db.delete(delivery).where(eq(delivery.noteId, noteId)).pipe(Effect.asVoid, Effect.orDie),
  save: (entry: DeliveryEntry) =>
    db
      .insert(delivery)
      .values(entry)
      .onConflictDoUpdate({ target: [delivery.noteId, delivery.lane], set: entry })
      .pipe(Effect.asVoid, Effect.orDie),
});
