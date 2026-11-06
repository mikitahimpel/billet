import { Context, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { Riddle } from "@billet/contracts-domain/riddle";
import type { RiddlesResponse } from "@billet/contracts-http-api/riddle";
import type { RiddleCommand, RiddleResult } from "@billet/backend-pair-room/riddle";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { NotesNotFound, NotesUnavailable, RiddleRefused } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/** What the routes answer: the riddles, or one riddle with a try's result. */
export type RiddleAnswer =
  | { readonly _tag: "Listed"; readonly view: RiddlesResponse }
  | { readonly _tag: "Changed"; readonly riddle: Riddle; readonly right?: boolean };

/**
 * The pair's draw-guess, for the caller's own pair: like notes, every call starts from the pair D1
 * says the caller belongs to. No partner is `NotesNotFound`.
 */
export class RiddleService extends Context.Service<
  RiddleService,
  {
    readonly run: (
      userId: UserId,
      command: RiddleCommand,
    ) => Effect.Effect<RiddleAnswer, NotesNotFound | NotesUnavailable | RiddleRefused>;
  }
>()("@billet/backend-notes/RiddleService") {
  static readonly layer: Layer.Layer<RiddleService, never, PairingRepository | PairRooms> =
    Layer.effect(
      RiddleService,
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

        const answer = (result: RiddleResult) => {
          switch (result._tag) {
            case "Listed":
            case "Changed":
              return Effect.succeed(result);
            case "Refused":
              return result.reason === "NotOpen"
                ? Effect.fail(new NotesNotFound())
                : Effect.fail(new RiddleRefused({ reason: result.reason }));
          }
        };

        const run = Effect.fn("RiddleService.run")(function* (
          userId: UserId,
          command: RiddleCommand,
        ) {
          const pairId = yield* pairOf(userId);
          const first = yield* rooms.riddle(pairId, userId, command);
          if (first._tag === "Refused" && first.reason === "NotOpen") {
            yield* openRoom(pairId);
            return yield* answer(yield* rooms.riddle(pairId, userId, command));
          }
          return yield* answer(first);
        });

        return RiddleService.of({ run });
      }),
    );
}
