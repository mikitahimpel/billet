import { Context, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { PickTonightResponse } from "@billet/contracts-http-api/pick-tonight";
import type { PickTonightCommand, PickTonightResult } from "@billet/backend-pair-room/pick-tonight";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/** Every call starts from the caller's pair in D1. No partner is `NotesNotFound`. */
export class PickTonightService extends Context.Service<
  PickTonightService,
  {
    readonly run: (
      userId: UserId,
      command: PickTonightCommand,
    ) => Effect.Effect<PickTonightResponse, NotesNotFound | NotesUnavailable>;
  }
>()("@billet/backend-notes/PickTonightService") {
  static readonly layer: Layer.Layer<PickTonightService, never, PairingRepository | PairRooms> =
    Layer.effect(
      PickTonightService,
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

        const answer = (result: PickTonightResult) => {
          switch (result._tag) {
            case "Done":
              return Effect.succeed(result.view);
            case "Refused":
              return Effect.fail(new NotesNotFound());
          }
        };

        const run = Effect.fn("PickTonightService.run")(function* (
          userId: UserId,
          command: PickTonightCommand,
        ) {
          const pairId = yield* pairOf(userId);
          const first = yield* rooms.pickTonight(pairId, userId, command);
          if (first._tag === "Refused") {
            yield* openRoom(pairId);
            return yield* answer(yield* rooms.pickTonight(pairId, userId, command));
          }
          return yield* answer(first);
        });

        return PickTonightService.of({ run });
      }),
    );
}
