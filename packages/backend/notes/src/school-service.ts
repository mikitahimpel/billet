import { Context, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { SchoolResponse } from "@billet/contracts-http-api/school";
import type { SchoolCommand, SchoolResult } from "@billet/backend-pair-room/school";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { InvalidSchool, NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/** Every call starts from the caller's pair in D1. No partner is `NotesNotFound`. */
export class SchoolService extends Context.Service<
  SchoolService,
  {
    readonly run: (
      userId: UserId,
      command: SchoolCommand,
    ) => Effect.Effect<SchoolResponse, NotesNotFound | InvalidSchool | NotesUnavailable>;
  }
>()("@billet/backend-notes/SchoolService") {
  static readonly layer: Layer.Layer<SchoolService, never, PairingRepository | PairRooms> =
    Layer.effect(
      SchoolService,
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

        const answer = (result: SchoolResult) => {
          switch (result._tag) {
            case "Done":
              return Effect.succeed(result.view);
            case "Refused":
              return Effect.fail(
                result.reason === "Invalid" ? new InvalidSchool() : new NotesNotFound(),
              );
          }
        };

        const run = Effect.fn("SchoolService.run")(function* (
          userId: UserId,
          command: SchoolCommand,
        ) {
          const pairId = yield* pairOf(userId);
          const first = yield* rooms.school(pairId, userId, command);
          if (first._tag === "Refused" && first.reason === "NotOpen") {
            yield* openRoom(pairId);
            return yield* answer(yield* rooms.school(pairId, userId, command));
          }
          return yield* answer(first);
        });

        return SchoolService.of({ run });
      }),
    );
}
