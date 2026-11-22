import { Context, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { StoryResponse } from "@billet/contracts-http-api/story";
import type { StoryCommand, StoryResult } from "@billet/backend-pair-room/story";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { InvalidStory, NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/** Every call starts from the caller's pair in D1. No partner is `NotesNotFound`. */
export class StoryService extends Context.Service<
  StoryService,
  {
    readonly run: (
      userId: UserId,
      command: StoryCommand,
    ) => Effect.Effect<StoryResponse, NotesNotFound | InvalidStory | NotesUnavailable>;
  }
>()("@billet/backend-notes/StoryService") {
  static readonly layer: Layer.Layer<StoryService, never, PairingRepository | PairRooms> =
    Layer.effect(
      StoryService,
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

        const answer = (result: StoryResult) => {
          switch (result._tag) {
            case "Done":
              return Effect.succeed(result.view);
            case "Refused":
              return Effect.fail(
                result.reason === "Full" ? new InvalidStory() : new NotesNotFound(),
              );
          }
        };

        const run = Effect.fn("StoryService.run")(function* (
          userId: UserId,
          command: StoryCommand,
        ) {
          const pairId = yield* pairOf(userId);
          const first = yield* rooms.story(pairId, userId, command);
          if (first._tag === "Refused" && first.reason === "NotOpen") {
            yield* openRoom(pairId);
            return yield* answer(yield* rooms.story(pairId, userId, command));
          }
          return yield* answer(first);
        });

        return StoryService.of({ run });
      }),
    );
}
