import { Context, Effect, Layer, Option, Schema } from "effect";
import { SecureRandom } from "effect/crypto";
import { type CatEntry, NatureSeed } from "@billet/contracts-domain/cat";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type {
  CatResponse,
  RecordCatEventRequest,
  RecordCatEventResponse,
  SaveCatRequest,
} from "@billet/contracts-http-api/cat";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import type { RoomDecision } from "@billet/backend-pair-room/room-decision";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { InvalidNote, NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

const isNotOpen = (decision: RoomDecision) =>
  decision._tag === "Rejected" && decision.rejection._tag === "RoomNotOpen";

const decodeSeed = Schema.decodeSync(NatureSeed);

/** Eight random bytes as a nonzero UInt64 in decimal. */
const seedFrom = (bytes: Uint8Array): NatureSeed => {
  let value = 0n;
  for (const byte of bytes) value = (value << 8n) | BigInt(byte);
  return decodeSeed(String(value === 0n ? 1n : value));
};

/**
 * The couple's cat, for the caller's own pair. Like notes, every method starts from the pair D1
 * says the caller belongs to, never one the client names. See docs/cat-state.md.
 */
export class CatService extends Context.Service<
  CatService,
  {
    readonly read: (userId: UserId) => Effect.Effect<CatResponse, NotesNotFound | NotesUnavailable>;
    /** Adopts the cat the first time, then renames it or changes its look. */
    readonly save: (
      userId: UserId,
      request: SaveCatRequest,
    ) => Effect.Effect<CatResponse, NotesNotFound | NotesUnavailable>;
    /** Appends one entry, or answers with the one already stored under its `id`. */
    readonly record: (
      userId: UserId,
      request: RecordCatEventRequest,
    ) => Effect.Effect<RecordCatEventResponse, NotesNotFound | InvalidNote | NotesUnavailable>;
    readonly journal: (
      userId: UserId,
      afterSeq: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<CatEntry>, NotesNotFound | NotesUnavailable>;
  }
>()("@billet/backend-notes/CatService") {
  static readonly layer: Layer.Layer<
    CatService,
    never,
    PairingRepository | PairRooms | SecureRandom.SecureRandom
  > = Layer.effect(
    CatService,
    Effect.gen(function* () {
      const pairing = yield* PairingRepository;
      const rooms = yield* PairRooms;
      const random = yield* SecureRandom.SecureRandom;

      const pairOf = (userId: UserId) =>
        pairing.findPair(userId).pipe(
          Effect.mapError(directoryUnavailable),
          Effect.flatMap(
            Option.match({
              onNone: () => Effect.fail(new NotesNotFound()),
              onSome: (pairId) => Effect.as(annotateRefs({ pair: pairId }), pairId),
            }),
          ),
        );

      // Pairing never reaches the room, so the first note or the first look at the cat opens it.
      const openRoom = Effect.fn("CatService.openRoom")(function* (pairId: PairId) {
        const [first, second] = yield* pairing
          .findMembers(pairId)
          .pipe(Effect.mapError(directoryUnavailable));
        if (first === undefined || second === undefined) {
          return yield* Effect.fail(new NotesNotFound());
        }
        yield* rooms.open(pairId, [first, second]);
      });

      const view = Effect.fn("CatService.view")(function* (pairId: PairId) {
        const now = yield* rooms.cat(pairId);
        if (now !== null) return now;
        yield* openRoom(pairId);
        const opened = yield* rooms.cat(pairId);
        if (opened === null)
          return yield* Effect.fail(new NotesUnavailable({ reason: "room-not-open" }));
        return opened;
      });

      const read = Effect.fn("CatService.read")(function* (userId: UserId) {
        return yield* view(yield* pairOf(userId));
      });

      const save = Effect.fn("CatService.save")(function* (
        userId: UserId,
        request: SaveCatRequest,
      ) {
        const pairId = yield* pairOf(userId);
        const seed = seedFrom(yield* random.randomBytes(8));
        const attempt = yield* rooms.saveCat(pairId, userId, request, seed);
        const decision = isNotOpen(attempt)
          ? yield* openRoom(pairId).pipe(
              Effect.andThen(rooms.saveCat(pairId, userId, request, seed)),
            )
          : attempt;
        if (decision._tag === "Rejected") {
          return yield* Effect.fail(new NotesUnavailable({ reason: "room-refused-cat" }));
        }
        return yield* view(pairId);
      });

      const record = Effect.fn("CatService.record")(function* (
        userId: UserId,
        request: RecordCatEventRequest,
      ): Effect.fn.Return<RecordCatEventResponse, NotesNotFound | InvalidNote | NotesUnavailable> {
        const pairId = yield* pairOf(userId);
        const decision = yield* rooms.recordCatEvent(pairId, userId, request);
        if (decision._tag === "Rejected") {
          switch (decision.rejection._tag) {
            // No room yet means no cat yet: there is nothing to care for.
            case "RoomNotOpen":
            case "CatNotAdopted":
              return yield* Effect.fail(new NotesNotFound());
            case "CatEntryIdTaken":
              return yield* Effect.fail(new InvalidNote());
            case "NotAMember":
            case "DuplicateMember":
            case "RoomAlreadyOpen":
            case "InkNotOwned":
            case "NotEnoughCoins":
            case "AlreadyOwned":
            case "NotSold":
            case "NoteNotFound":
            case "OwnNote":
            case "NotReactable":
            case "NoReaction":
              return yield* Effect.fail(new NotesUnavailable({ reason: "room-refused-cat-event" }));
          }
        }
        const entry = decision.outputs.flatMap((output) =>
          output._tag === "CatEntryAppended" || output._tag === "CatEntryRepeated"
            ? [output.entry]
            : [],
        )[0];
        if (entry === undefined) {
          return yield* Effect.fail(new NotesUnavailable({ reason: "cat-entry-not-appended" }));
        }
        const { temper, needs } = yield* view(pairId);
        return { entry, temper, needs };
      });

      const journal = Effect.fn("CatService.journal")(function* (
        userId: UserId,
        afterSeq: number,
        limit: number,
      ) {
        return yield* rooms.catJournal(yield* pairOf(userId), afterSeq, limit);
      });

      return CatService.of({ read, save, record, journal });
    }),
  );
}
