import { Effect, Layer, Option, Schema } from "effect";
import { SecureRandom } from "effect/crypto";
import { NoteId, UserId, type MediaKey } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { Metrics, type MetricEvent } from "@billet/backend-metrics/metrics";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import { NoteIdSource } from "@billet/backend-pair-room/note-id-source";
import { RoomService } from "@billet/backend-pair-room/room-service";
import type { ActiveRoom, RoomState, SequencedNote } from "@billet/backend-pair-room/room-state";
import { RoomStore, type AppendedNote } from "@billet/backend-pair-room/room-store";
import { MediaStore, mediaPrefix } from "../src/media-store.ts";
import { PairRooms } from "../src/pair-rooms.ts";

export const user = Schema.decodeSync(UserId);
export const pair = Schema.decodeSync(PairId);

/** The real room rules on memory. */
const makeRoom = () => {
  let state: RoomState = { _tag: "Vacant" };
  let notes: Array<SequencedNote> = [];
  let nextNote = 0;
  const keys = new Map<string, SequencedNote>();
  const store = Layer.succeed(RoomStore, {
    load: Effect.sync(() => state),
    commit: (room: ActiveRoom, appended: ReadonlyArray<AppendedNote>) =>
      Effect.sync(() => {
        state = room;
        for (const { entry, key } of appended) {
          notes.push(entry);
          keys.set(`${entry.note.author}/${key}`, entry);
        }
      }),
    noteByKey: (author, key) =>
      Effect.sync(() => Option.fromNullishOr(keys.get(`${author}/${key}`))),
    notesAfter: (afterSeq: number, limit: number) =>
      Effect.sync(() => notes.filter(({ seq }) => seq > afterSeq).slice(0, limit)),
    forgetAuthor: (author) =>
      Effect.sync(() => {
        const forgotten = notes.filter(({ note }) => note.author === author);
        notes = notes.filter(({ note }) => note.author !== author);
        for (const [key, entry] of keys) if (entry.note.author === author) keys.delete(key);
        return forgotten;
      }),
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
  const recorded: Array<MetricEvent> = [];

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

  const uploaders = new Map<MediaKey, UserId>();
  const media: MediaStore["Service"] = {
    put: (key, bytes, uploader) =>
      Effect.sync(() => {
        objects.set(key, bytes);
        uploaders.set(key, uploader);
      }),
    get: (key) => Effect.sync(() => Option.fromNullishOr(objects.get(key))),
    has: (key) => Effect.sync(() => objects.has(key)),
    uploadedBy: (pairId, uploader) =>
      Effect.sync(() =>
        [...objects.keys()].filter(
          (key) => key.startsWith(mediaPrefix(pairId)) && uploaders.get(key) === uploader,
        ),
      ),
    remove: (keys) =>
      Effect.sync(() => {
        for (const key of keys) {
          objects.delete(key);
          uploaders.delete(key);
        }
      }),
  };

  const pairRooms: PairRooms["Service"] = {
    open: (pairId, members) => roomOf(pairId).dispatch({ _tag: "Open", pairId, members }),
    sendNote: (pairId, author, request) => roomOf(pairId).sendNote(author, request),
    notesAfter: (pairId, afterSeq, limit) => roomOf(pairId).notesAfter(afterSeq, limit),
    forgetMember: (pairId, user) => roomOf(pairId).forgetAuthor(user),
  };

  return {
    objects,
    recorded,
    media,
    pairRooms,
    repository,
    layer: Layer.mergeAll(
      Layer.succeed(PairingRepository, repository),
      Layer.succeed(MediaStore, media),
      Layer.succeed(PairRooms, pairRooms),
      Layer.succeed(Metrics, { record: (event) => Effect.sync(() => void recorded.push(event)) }),
      SecureRandom.layerWebCrypto,
    ),
  };
};
