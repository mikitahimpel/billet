import { Context, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { GuessResponse } from "@billet/contracts-http-api/guess";
import type { GuessCommand, GuessResult } from "@billet/backend-pair-room/guess";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { GuessRefused, NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/**
 * The pair's Who knows who round, for the caller's own pair: like notes, every call starts from the
 * pair D1 says the caller belongs to. No partner is `NotesNotFound`.
 */
export class GuessService extends Context.Service<
  GuessService,
  {
    readonly run: (
      userId: UserId,
      command: GuessCommand,
    ) => Effect.Effect<GuessResponse, NotesNotFound | NotesUnavailable | GuessRefused>;
  }
>()("@billet/backend-notes/GuessService") {
  static readonly layer: Layer.Layer<GuessService, never, PairingRepository | PairRooms> =
    Layer.effect(
      GuessService,
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

        // Pairing never reaches the room, so the first call of a pair opens it.
        const openRoom = (pairId: PairId) =>
          Effect.gen(function* () {
            const [first, second] = yield* pairing
              .findMembers(pairId)
              .pipe(Effect.mapError(directoryUnavailable));
            if (first === undefined || second === undefined) {
              return yield* Effect.fail(new NotesNotFound());
            }
            yield* rooms.open(pairId, [first, second]);
          });

        const answer = (result: GuessResult) => {
          if (result._tag === "Done") return Effect.succeed(result.view);
          switch (result.reason) {
            case "NotOpen":
              return Effect.fail(new NotesNotFound());
            case "RoundClosed":
            case "NotInRound":
            case "Answered":
              return Effect.fail(new GuessRefused({ reason: result.reason }));
          }
        };

        const run = Effect.fn("GuessService.run")(function* (
          userId: UserId,
          command: GuessCommand,
        ) {
          const pairId = yield* pairOf(userId);
          const first = yield* rooms.guess(pairId, userId, command);
          if (first._tag === "Refused" && first.reason === "NotOpen") {
            yield* openRoom(pairId);
            return yield* answer(yield* rooms.guess(pairId, userId, command));
          }
          return yield* answer(first);
        });

        return GuessService.of({ run });
      }),
    );
}
