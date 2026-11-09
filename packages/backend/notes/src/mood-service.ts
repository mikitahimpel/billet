import { Context, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { MoodCheckIn } from "@billet/contracts-domain/mood";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { SetMoodRequest } from "@billet/contracts-http-api/mood";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import type { RoomDecision } from "@billet/backend-pair-room/room-decision";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { InvalidNote, NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

const isNotOpen = (decision: RoomDecision) =>
  decision._tag === "Rejected" && decision.rejection._tag === "RoomNotOpen";

/**
 * Each partner's "How are you", for the caller's own pair. Like notes, every method starts from
 * the pair D1 says the caller belongs to, never one the client names.
 */
export class MoodService extends Context.Service<
  MoodService,
  {
    /** Replaces the caller's check-in and answers with it. A note too long is `InvalidNote`. */
    readonly set: (
      userId: UserId,
      request: SetMoodRequest,
    ) => Effect.Effect<MoodCheckIn, NotesNotFound | InvalidNote | NotesUnavailable>;
    /** Each member's latest check-in. A room not opened yet has none. */
    readonly latest: (
      pairId: PairId,
    ) => Effect.Effect<ReadonlyArray<MoodCheckIn>, NotesUnavailable>;
  }
>()("@billet/backend-notes/MoodService") {
  static readonly layer: Layer.Layer<MoodService, never, PairingRepository | PairRooms> =
    Layer.effect(
      MoodService,
      Effect.gen(function* () {
        const pairing = yield* PairingRepository;
        const rooms = yield* PairRooms;

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

        // Pairing may not have reached the room, so the first check-in opens it.
        const openRoom = Effect.fn("MoodService.openRoom")(function* (pairId: PairId) {
          const [first, second] = yield* pairing
            .findMembers(pairId)
            .pipe(Effect.mapError(directoryUnavailable));
          if (first === undefined || second === undefined) {
            return yield* Effect.fail(new NotesNotFound());
          }
          yield* rooms.open(pairId, [first, second]);
        });

        const set = Effect.fn("MoodService.set")(function* (
          userId: UserId,
          request: SetMoodRequest,
        ): Effect.fn.Return<MoodCheckIn, NotesNotFound | InvalidNote | NotesUnavailable> {
          const pairId = yield* pairOf(userId);
          const attempt = yield* rooms.setMood(pairId, userId, request);
          const decision = isNotOpen(attempt)
            ? yield* openRoom(pairId).pipe(Effect.andThen(rooms.setMood(pairId, userId, request)))
            : attempt;
          if (decision._tag === "Rejected") {
            switch (decision.rejection._tag) {
              case "MoodNoteTooLong":
                return yield* Effect.fail(new InvalidNote());
              // The directory and the room disagree on who is in the pair.
              case "NotAMember":
              case "RoomNotOpen":
                return yield* Effect.fail(new NotesNotFound());
              case "DuplicateMember":
              case "RoomAlreadyOpen":
              case "CatNotAdopted":
              case "CatEntryIdTaken":
              case "InkNotOwned":
              case "NotEnoughCoins":
              case "PriceChanged":
              case "AlreadyOwned":
              case "NotSold":
              case "OfferOwned":
              case "NotOffered":
              case "NoteNotFound":
              case "OwnNote":
              case "NotReactable":
              case "NoReaction":
              case "GiftTaken":
              case "CollectionIncomplete":
              case "BonusTaken":
              case "ListNotFound":
              case "ListItemNotFound":
              case "RoomJournalsGame":
              case "StreakNotRestorable":
                return yield* Effect.fail(new NotesUnavailable({ reason: "room-refused-mood" }));
            }
          }
          const checkIn = decision.outputs.flatMap((output) =>
            output._tag === "MoodSet" ? [output.checkIn] : [],
          )[0];
          if (checkIn === undefined) {
            return yield* Effect.fail(new NotesUnavailable({ reason: "mood-not-set" }));
          }
          return checkIn;
        });

        const latest = Effect.fn("MoodService.latest")(function* (pairId: PairId) {
          return yield* rooms.moods(pairId);
        });

        return MoodService.of({ set, latest });
      }),
    );
}
