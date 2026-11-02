import { Context, Effect, Layer, Option, Schema } from "effect";
import { SecureRandom } from "effect/crypto";
import { MediaKey, type UserId } from "@billet/contracts-domain/ids";
import type { CompactStrokes } from "@billet/contracts-domain/ink";
import type { Note } from "@billet/contracts-domain/note";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { SendNoteRequest } from "@billet/contracts-http-api/note";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import type { RoomDecision } from "@billet/backend-pair-room/room-decision";
import { MediaStore, mediaPrefix } from "./media-store.ts";
import { InvalidNote, NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

/** The most a compact rendition may take as JSON, matching the iOS encoder's budget. */
export const compactBudget = 3072;

const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

const isPng = (bytes: Uint8Array) => pngSignature.every((byte, index) => bytes[index] === byte);

const encoder = new TextEncoder();

const compactFits = (compact: CompactStrokes) =>
  encoder.encode(JSON.stringify(compact)).length <= compactBudget;

const decodeMediaKey = Schema.decodeSync(MediaKey);

const belongsTo = (pairId: PairId, key: MediaKey) => key.startsWith(mediaPrefix(pairId));

const isNotOpen = (decision: RoomDecision) =>
  decision._tag === "Rejected" && decision.rejection._tag === "RoomNotOpen";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/**
 * Notes and their images, for the caller's own pair. Every method starts from the pair that D1 says
 * the caller belongs to, never from one the client names, so one couple can't reach another's room
 * or prefix.
 */
export class NotesService extends Context.Service<
  NotesService,
  {
    /** Stores a PNG under the couple's prefix and returns its new key. */
    readonly uploadImage: (
      userId: UserId,
      bytes: Uint8Array,
    ) => Effect.Effect<MediaKey, NotesNotFound | InvalidNote | NotesUnavailable>;
    readonly readImage: (
      userId: UserId,
      key: MediaKey,
    ) => Effect.Effect<Uint8Array, NotesNotFound | NotesUnavailable>;
    /** Appends a note to the room. Its image must already be in the couple's prefix. */
    readonly sendNote: (
      userId: UserId,
      request: SendNoteRequest,
    ) => Effect.Effect<Note, NotesNotFound | InvalidNote | NotesUnavailable>;
    /** The couple's notes with `seq` above `afterSeq`, oldest first. */
    readonly history: (
      userId: UserId,
      afterSeq: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<Note>, NotesNotFound | NotesUnavailable>;
  }
>()("@billet/backend-notes/NotesService") {
  static readonly layer: Layer.Layer<
    NotesService,
    never,
    PairingRepository | MediaStore | PairRooms | SecureRandom.SecureRandom
  > = Layer.effect(
    NotesService,
    Effect.gen(function* () {
      const pairing = yield* PairingRepository;
      const media = yield* MediaStore;
      const rooms = yield* PairRooms;
      const random = yield* SecureRandom.SecureRandom;

      const pairOf = (userId: UserId) =>
        pairing.findPair(userId).pipe(
          Effect.mapError(directoryUnavailable),
          Effect.flatMap(
            Option.match({
              onNone: () => Effect.fail(new NotesNotFound()),
              onSome: (pairId) => Effect.succeed(pairId),
            }),
          ),
        );

      // Pairing commits in D1 and never reaches the room, so a couple's first note opens it. Two
      // first notes at once both open it, and a repeated open is accepted.
      const openRoom = Effect.fnUntraced(function* (pairId: PairId) {
        const members = yield* pairing
          .findMembers(pairId)
          .pipe(Effect.mapError(directoryUnavailable));
        const [first, second] = members;
        if (first === undefined || second === undefined) {
          return yield* Effect.fail(new NotesNotFound());
        }
        yield* rooms.open(pairId, [first, second]);
      });

      const uploadImage = Effect.fnUntraced(function* (
        userId: UserId,
        bytes: Uint8Array,
      ): Effect.fn.Return<MediaKey, NotesNotFound | InvalidNote | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        if (!isPng(bytes)) return yield* Effect.fail(new InvalidNote());
        const id = yield* random.uuidV4();
        const key = decodeMediaKey(`${mediaPrefix(pairId)}notes/${id}.png`);
        yield* media.put(key, bytes);
        return key;
      });

      const readImage = Effect.fnUntraced(function* (
        userId: UserId,
        key: MediaKey,
      ): Effect.fn.Return<Uint8Array, NotesNotFound | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        if (!belongsTo(pairId, key)) return yield* Effect.fail(new NotesNotFound());
        const image = yield* media.get(key);
        return yield* Option.match(image, {
          onNone: () => Effect.fail(new NotesNotFound()),
          onSome: (bytes) => Effect.succeed(bytes),
        });
      });

      const sendNote = Effect.fnUntraced(function* (
        userId: UserId,
        request: SendNoteRequest,
      ): Effect.fn.Return<Note, NotesNotFound | InvalidNote | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        if (request._tag === "Drawing" && !compactFits(request.compact)) {
          return yield* Effect.fail(new InvalidNote());
        }
        if (!belongsTo(pairId, request.image) || !(yield* media.has(request.image))) {
          return yield* Effect.fail(new NotesNotFound());
        }

        const attempt = yield* rooms.sendNote(pairId, userId, request);
        const decision = isNotOpen(attempt)
          ? yield* openRoom(pairId).pipe(Effect.andThen(rooms.sendNote(pairId, userId, request)))
          : attempt;

        switch (decision._tag) {
          case "Accepted": {
            const appended = decision.outputs.find((output) => output._tag === "NoteAppended");
            if (appended !== undefined) return appended.entry.note;
            return yield* Effect.fail(new NotesUnavailable({ reason: "note-not-appended" }));
          }
          case "Rejected":
            return yield* Effect.fail(new NotesUnavailable({ reason: "room-refused-note" }));
        }
      });

      const history = Effect.fnUntraced(function* (
        userId: UserId,
        afterSeq: number,
        limit: number,
      ): Effect.fn.Return<ReadonlyArray<Note>, NotesNotFound | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        const entries = yield* rooms.notesAfter(pairId, afterSeq, limit);
        return entries.map(({ note }) => note);
      });

      return NotesService.of({ uploadImage, readImage, sendNote, history });
    }),
  );
}
