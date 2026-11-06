import { Effect, Layer, Schema } from "effect";
import { NoteId } from "@billet/contracts-domain/ids";
import { questionCatalog } from "@billet/backend-guess/question-catalog";
import { NoteIdSource } from "@billet/backend-pair-room/note-id-source";
import { GiftsRoom } from "@billet/backend-pair-room/gifts";
import { GuessDeck, GuessRoom } from "@billet/backend-pair-room/guess";
import { PickTonightRoom } from "@billet/backend-pair-room/pick-tonight";
import { RoomService } from "@billet/backend-pair-room/room-service";
import { SqliteGiftsStore } from "./pair-room-gifts-store.ts";
import { SqliteGuessStore } from "./pair-room-guess-store.ts";
import { SqlitePickTonightStore } from "./pair-room-pick-tonight-store.ts";
import { RoomDb, SqliteRoomStore } from "./pair-room-sqlite-store.ts";

const decodeNoteId = Schema.decodeSync(NoteId);

const RandomNoteIds = Layer.succeed(NoteIdSource, {
  next: Effect.sync(() => decodeNoteId(crypto.randomUUID())),
});

const CatalogDeck = Layer.succeed(GuessDeck, {
  questions: questionCatalog.questions.map((question) => question.id),
});

/**
 * The service graph of one room. It still requires `RoomDb`, given once at the object edge. Who
 * knows who pays its coins through the room's one `RoomService`, so both share its lock.
 */
export const PairRoomLive: Layer.Layer<
  RoomService | GiftsRoom | PickTonightRoom | GuessRoom,
  never,
  RoomDb
> = Layer.mergeAll(GiftsRoom.layer, PickTonightRoom.layer, GuessRoom.layer).pipe(
  Layer.provideMerge(RoomService.layer),
  Layer.provide(
    Layer.mergeAll(
      SqliteRoomStore,
      SqliteGiftsStore,
      SqlitePickTonightStore,
      SqliteGuessStore,
      RandomNoteIds,
      CatalogDeck,
    ),
  ),
);
