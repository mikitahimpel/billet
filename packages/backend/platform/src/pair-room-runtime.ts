import { Effect, Layer, Schema } from "effect";
import { NoteId } from "@billet/contracts-domain/ids";
import { NoteIdSource } from "@billet/backend-pair-room/note-id-source";
import { GiftsRoom } from "@billet/backend-pair-room/gifts";
import { PickTonightRoom } from "@billet/backend-pair-room/pick-tonight";
import { RoomService } from "@billet/backend-pair-room/room-service";
import { SqliteGiftsStore } from "./pair-room-gifts-store.ts";
import { SqlitePickTonightStore } from "./pair-room-pick-tonight-store.ts";
import { RoomDb, SqliteRoomStore } from "./pair-room-sqlite-store.ts";

const decodeNoteId = Schema.decodeSync(NoteId);

const RandomNoteIds = Layer.succeed(NoteIdSource, {
  next: Effect.sync(() => decodeNoteId(crypto.randomUUID())),
});

/** The service graph of one room. It still requires `RoomDb`, given once at the object edge. */
export const PairRoomLive: Layer.Layer<RoomService | GiftsRoom | PickTonightRoom, never, RoomDb> =
  Layer.mergeAll(RoomService.layer, GiftsRoom.layer, PickTonightRoom.layer).pipe(
    Layer.provide(
      Layer.mergeAll(SqliteRoomStore, SqliteGiftsStore, SqlitePickTonightStore, RandomNoteIds),
    ),
  );
