import { Context, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { ChangeListRequest, ListsResponse } from "@billet/contracts-http-api/lists";
import type { ListsResult } from "@billet/backend-pair-room/lists";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/**
 * The pair's shared lists, for the caller's own pair: like notes, every call starts from the pair
 * D1 says the caller belongs to. No partner, or a list or item that is gone, is `NotesNotFound`.
 */
export class ListsService extends Context.Service<
  ListsService,
  {
    readonly run: (
      userId: UserId,
      request: ChangeListRequest | undefined,
    ) => Effect.Effect<ListsResponse, NotesNotFound | NotesUnavailable>;
  }
>()("@billet/backend-notes/ListsService") {
  static readonly layer: Layer.Layer<ListsService, never, PairingRepository | PairRooms> =
    Layer.effect(
      ListsService,
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

        // Pairing never reaches the room, so the first list call of a pair opens it.
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

        const answer = (result: ListsResult) => {
          switch (result._tag) {
            case "Done":
              return Effect.succeed({ lists: result.lists });
            case "Refused":
              return Effect.fail(new NotesNotFound());
          }
        };

        const run = Effect.fn("ListsService.run")(function* (
          userId: UserId,
          request: ChangeListRequest | undefined,
        ) {
          const pairId = yield* pairOf(userId);
          const first = yield* rooms.lists(pairId, userId, request);
          if (first._tag === "Refused" && first.reason === "NotOpen") {
            yield* openRoom(pairId);
            return yield* answer(yield* rooms.lists(pairId, userId, request));
          }
          return yield* answer(first);
        });

        return ListsService.of({ run });
      }),
    );
}
