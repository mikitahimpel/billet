import { Context, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { emptyStreak, type LoveStreak } from "@billet/contracts-domain/streak";
import type {
  RecordStreakDayRequest,
  RestoreStreakRequest,
} from "@billet/contracts-http-api/streak";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import type { RoomDecision } from "@billet/backend-pair-room/room-decision";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { NotesNotFound, NotesUnavailable, StreakNotRestorable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

const isNotOpen = (decision: RoomDecision) =>
  decision._tag === "Rejected" && decision.rejection._tag === "RoomNotOpen";

/** Every method starts from the caller's pair in D1, never from one the client names. */
export class StreakService extends Context.Service<
  StreakService,
  {
    /** The pair's streak; empty before the room opens. */
    readonly get: (userId: UserId) => Effect.Effect<LoveStreak, NotesNotFound | NotesUnavailable>;
    readonly recordDay: (
      userId: UserId,
      request: RecordStreakDayRequest,
    ) => Effect.Effect<LoveStreak, NotesNotFound | NotesUnavailable>;
    readonly restore: (
      userId: UserId,
      request: RestoreStreakRequest,
    ) => Effect.Effect<LoveStreak, NotesNotFound | StreakNotRestorable | NotesUnavailable>;
  }
>()("@billet/backend-notes/StreakService") {
  static readonly layer: Layer.Layer<StreakService, never, PairingRepository | PairRooms> =
    Layer.effect(
      StreakService,
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

        // Pairing may not have reached the room, so the first day opens it.
        const openRoom = Effect.fn("StreakService.openRoom")(function* (pairId: PairId) {
          const [first, second] = yield* pairing
            .findMembers(pairId)
            .pipe(Effect.mapError(directoryUnavailable));
          if (first === undefined || second === undefined) {
            return yield* Effect.fail(new NotesNotFound());
          }
          yield* rooms.open(pairId, [first, second]);
        });

        /** The streak an accepted decision leaves, or how the room refused it. */
        const streakAfter = Effect.fn("StreakService.streakAfter")(function* (
          decision: RoomDecision,
        ): Effect.fn.Return<LoveStreak, NotesNotFound | StreakNotRestorable | NotesUnavailable> {
          switch (decision._tag) {
            case "Accepted":
              return decision.state.streak;
            case "Rejected":
              switch (decision.rejection._tag) {
                case "StreakNotRestorable":
                  return yield* Effect.fail(new StreakNotRestorable());
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
                case "MoodNoteTooLong":
                case "RoomJournalsGame":
                  return yield* Effect.fail(
                    new NotesUnavailable({ reason: "room-refused-streak" }),
                  );
              }
          }
        });

        const get = Effect.fn("StreakService.get")(function* (userId: UserId) {
          const streak = yield* rooms.streak(yield* pairOf(userId));
          return streak ?? emptyStreak;
        });

        const recordDay = Effect.fn("StreakService.recordDay")(function* (
          userId: UserId,
          request: RecordStreakDayRequest,
        ): Effect.fn.Return<LoveStreak, NotesNotFound | NotesUnavailable> {
          const pairId = yield* pairOf(userId);
          const attempt = yield* rooms.recordStreakDay(pairId, userId, request);
          const decision = isNotOpen(attempt)
            ? yield* openRoom(pairId).pipe(
                Effect.andThen(rooms.recordStreakDay(pairId, userId, request)),
              )
            : attempt;
          return yield* streakAfter(decision).pipe(
            Effect.catchTag("StreakNotRestorable", () =>
              Effect.fail(new NotesUnavailable({ reason: "room-refused-streak" })),
            ),
          );
        });

        const restore = Effect.fn("StreakService.restore")(function* (
          userId: UserId,
          request: RestoreStreakRequest,
        ) {
          const pairId = yield* pairOf(userId);
          return yield* streakAfter(yield* rooms.restoreStreak(pairId, userId, request));
        });

        return StreakService.of({ get, recordDay, restore });
      }),
    );
}
