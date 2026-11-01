import { Effect, Layer, Option, Schema } from "effect";
import { SecureRandom } from "effect/crypto";
import { NoteId, UserId, type MediaKey } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import { NoteIdSource } from "@billet/backend-pair-room/note-id-source";
import { RoomService } from "@billet/backend-pair-room/room-service";
import type { ActiveRoom, RoomState, SequencedNote } from "@billet/backend-pair-room/room-state";
import { RoomStore } from "@billet/backend-pair-room/room-store";
import { MediaStore } from "../src/media-store.ts";
import { PairRooms } from "../src/pair-rooms.ts";

export const user = Schema.decodeSync(UserId);
export const pair = Schema.decodeSync(PairId);

/** The real room rules on memory. */
const makeRoom = () => {
  let state: RoomState = { _tag: "Vacant" };
  const notes: Array<SequencedNote> = [];
  let nextNote = 0;
  const store = Layer.succeed(RoomStore, {
    load: Effect.sync(() => state),
    commit: (room: ActiveRoom, appended: ReadonlyArray<SequencedNote>) =>
      Effect.sync(() => {
        state = room;
        notes.push(...appended);
      }),
    notesAfter: (afterSeq: number, limit: number) =>
      Effect.sync(() => notes.filter(({ seq }) => seq > afterSeq).slice(0, limit)),
  });
  const ids = Layer.succeed(NoteIdSource, {
    next: Effect.sync(() => Schema.decodeSync(NoteId)(`note-${(nextNote += 1)}`)),
  });
  return Effect.runSync(RoomService.make.pipe(Effect.provide(Layer.merge(store, ids))));
};

/** Memory-backed dependencies for the given couples. `pairs` is `[pairId, first, second]`. */
export const makeWorld = (pairs: ReadonlyArray<readonly [PairId, UserId, UserId]>) => {
  const objects = new Map<MediaKey, Uint8Array>();
  const rooms = new Map<PairId, ReturnType<typeof makeRoom>>();

  const roomOf = (pairId: PairId) => {
    const room = rooms.get(pairId) ?? makeRoom();
    rooms.set(pairId, room);
    return room;
  };

  const repository: PairingRepository["Service"] = {
    ...makeInMemoryPairingRepository().repository,
    findPair: (userId) =>
      Effect.succeed(
        Option.fromNullishOr(pairs.find(([, ...members]) => members.includes(userId))?.[0]),
      ),
    findMembers: (pairId) =>
      Effect.sync(() => {
        const row = pairs.find(([id]) => id === pairId);
        return row === undefined ? [] : [row[1], row[2]];
      }),
  };

  const media: MediaStore["Service"] = {
    put: (key, bytes) => Effect.sync(() => void objects.set(key, bytes)),
    get: (key) => Effect.sync(() => Option.fromNullishOr(objects.get(key))),
    has: (key) => Effect.sync(() => objects.has(key)),
  };

  const pairRooms: PairRooms["Service"] = {
    open: (pairId, members) => roomOf(pairId).dispatch({ _tag: "Open", pairId, members }),
    sendNote: (pairId, author, request) => roomOf(pairId).sendNote(author, request),
    notesAfter: (pairId, afterSeq, limit) => roomOf(pairId).notesAfter(afterSeq, limit),
  };

  return {
    objects,
    media,
    pairRooms,
    repository,
    layer: Layer.mergeAll(
      Layer.succeed(PairingRepository, repository),
      Layer.succeed(MediaStore, media),
      Layer.succeed(PairRooms, pairRooms),
      SecureRandom.layerWebCrypto,
    ),
  };
};
