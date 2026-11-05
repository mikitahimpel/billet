import { Schema } from "effect";
import {
  CatEntry,
  CatEvent,
  CatLook,
  CatName,
  CatNeeds,
  CatProfile,
  CatTemper,
  UtcOffsetSeconds,
} from "@billet/contracts-domain/cat";
import { IdempotencyKey } from "@billet/contracts-domain/ids";

/**
 * The couple's cat now. `cat` is absent until one of them adopts it; `temper` and `needs` are then
 * those of a cat just born. `lastSeq` is the journal's last entry, 0 when it is empty.
 */
export const CatResponse = Schema.Struct({
  cat: Schema.optionalKey(CatProfile),
  temper: CatTemper,
  needs: CatNeeds,
  lastSeq: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
});
export type CatResponse = typeof CatResponse.Type;

/** The first save adopts the cat; later saves change its name, look and the pair's clock. */
export const SaveCatRequest = Schema.Struct({
  name: CatName,
  look: CatLook,
  utcOffsetSeconds: UtcOffsetSeconds,
});
export type SaveCatRequest = typeof SaveCatRequest.Type;

/** What a phone may record. `NoteShared` is the room's own, written when a note is stored. */
export const RecordableCatEvent = CatEvent.check(
  Schema.makeFilter((event) => event._tag !== "NoteShared" || "the room records notes itself"),
);

/** `id` is a UUID the phone makes once and repeats on every retry of the same event. */
export const RecordCatEventRequest = Schema.Struct({
  id: IdempotencyKey,
  event: RecordableCatEvent,
});
export type RecordCatEventRequest = typeof RecordCatEventRequest.Type;

/** The stored entry, or the first one under the same `id`, with the cat as it now is. */
export const RecordCatEventResponse = Schema.Struct({
  entry: CatEntry,
  temper: CatTemper,
  needs: CatNeeds,
});
export type RecordCatEventResponse = typeof RecordCatEventResponse.Type;

/** Oldest first. The next page starts after the last entry's `seq`. */
export const CatJournalResponse = Schema.Struct({ entries: Schema.Array(CatEntry) });
export type CatJournalResponse = typeof CatJournalResponse.Type;
