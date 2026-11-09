import { Effect, Layer, Schema } from "effect";
import { NoteId } from "@billet/contracts-domain/ids";
import { questionCatalog } from "@billet/backend-guess/question-catalog";
import { NoteIdSource } from "@billet/backend-pair-room/note-id-source";
import { GiftsRoom } from "@billet/backend-pair-room/gifts";
import { GuessDeck, GuessRoom } from "@billet/backend-pair-room/guess";
import { PickTonightRoom } from "@billet/backend-pair-room/pick-tonight";
import { RiddleRoom } from "@billet/backend-pair-room/riddle";
import { RoomService } from "@billet/backend-pair-room/room-service";
import { SqliteGiftsStore } from "./pair-room-gifts-store.ts";
import { SqliteGuessStore } from "./pair-room-guess-store.ts";
import { SqlitePickTonightStore } from "./pair-room-pick-tonight-store.ts";
import { SqliteRiddleStore } from "./pair-room-riddle-store.ts";
import { RoomDb, SqliteRoomStore } from "./pair-room-sqlite-store.ts";

const decodeNoteId = Schema.decodeSync(NoteId);

const RandomNoteIds = Layer.succeed(NoteIdSource, {
  next: Effect.sync(() => decodeNoteId(crypto.randomUUID())),
});

const CatalogDeck = Layer.succeed(GuessDeck, {
  questions: questionCatalog.questions.map((question) => question.id),
});

/**
 * Needs `RoomDb`. Who knows who and draw-guess commit through `RoomService`, sharing its lock.
 */
export const PairRoomLive: Layer.Layer<
  RoomService | GiftsRoom | PickTonightRoom | GuessRoom | RiddleRoom,
  never,
  RoomDb
> = Layer.mergeAll(GiftsRoom.layer, PickTonightRoom.layer, GuessRoom.layer, RiddleRoom.layer).pipe(
  Layer.provideMerge(RoomService.layer),
  Layer.provide(
    Layer.mergeAll(
      SqliteRoomStore,
      SqliteGiftsStore,
      SqlitePickTonightStore,
      SqliteGuessStore,
      SqliteRiddleStore,
      RandomNoteIds,
      CatalogDeck,
    ),
  ),
);
