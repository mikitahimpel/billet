import { Context, Data, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { GiftsResponse } from "@billet/contracts-http-api/gifts";
import type { GiftCommand, GiftsResult } from "@billet/backend-pair-room/gifts";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

/** A change that is not the caller's to make: someone else's wish, or a plan for their own. */
export class GiftNotAllowed extends Data.TaggedError("GiftNotAllowed") {}

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/** Every call starts from the caller's pair in D1. No partner or no such wish: `NotesNotFound`. */
export class GiftsService extends Context.Service<
  GiftsService,
  {
    readonly run: (
      userId: UserId,
      command: GiftCommand,
    ) => Effect.Effect<GiftsResponse, NotesNotFound | GiftNotAllowed | NotesUnavailable>;
  }
>()("@billet/backend-notes/GiftsService") {
  static readonly layer: Layer.Layer<GiftsService, never, PairingRepository | PairRooms> =
    Layer.effect(
      GiftsService,
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

        // Pairing never reaches the room, so the first gift call of a pair opens it.
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

        const answer = (result: GiftsResult) => {
          switch (result._tag) {
            case "Done":
              return Effect.succeed(result.view);
            case "Refused":
              switch (result.reason) {
                case "NotFound":
                case "NotOpen":
                  return Effect.fail(new NotesNotFound());
                case "NotAllowed":
                case "Taken":
                  return Effect.fail(new GiftNotAllowed());
              }
          }
        };

        const run = Effect.fn("GiftsService.run")(function* (userId: UserId, command: GiftCommand) {
          const pairId = yield* pairOf(userId);
          const first = yield* rooms.gifts(pairId, userId, command);
          if (first._tag === "Refused" && first.reason === "NotOpen") {
            yield* openRoom(pairId);
            return yield* answer(yield* rooms.gifts(pairId, userId, command));
          }
          return yield* answer(first);
        });

        return GiftsService.of({ run });
      }),
    );
}
