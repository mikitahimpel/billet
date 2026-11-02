import { Effect, Layer, Schema } from "effect";
import { NoteId } from "@billet/contracts-domain/ids";
import { NoteIdSource } from "@billet/backend-pair-room/note-id-source";
import { RoomService } from "@billet/backend-pair-room/room-service";
import { RoomDb, SqliteRoomStore } from "./pair-room-sqlite-store.ts";

const decodeNoteId = Schema.decodeSync(NoteId);

const RandomNoteIds = Layer.succeed(NoteIdSource, {
  next: Effect.sync(() => decodeNoteId(crypto.randomUUID())),
});

/** The service graph of one room. It still requires `RoomDb`, given once at the object edge. */
export const PairRoomLive: Layer.Layer<RoomService, never, RoomDb> = RoomService.layer.pipe(
  Layer.provide(Layer.merge(SqliteRoomStore, RandomNoteIds)),
);
