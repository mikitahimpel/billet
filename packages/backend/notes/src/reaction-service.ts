import { Context, Effect, Layer, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { NoteReaction } from "@billet/contracts-domain/reaction";
import type { ReactRequest } from "@billet/contracts-http-api/reaction";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { InvalidNote, NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/**
 * Reactions to the partner's photos, for the caller's own pair. Like notes, every method starts
 * from the pair D1 says the caller belongs to, never one the client names.
 */
export class ReactionService extends Context.Service<
  ReactionService,
  {
    /**
     * Sets or takes back the caller's reaction and answers with it. A note the room does not
     * hold, or a take-back of nothing, is `NotesNotFound`; their own note or one that is not a
     * photo is `InvalidNote`.
     */
    readonly react: (
      userId: UserId,
      request: ReactRequest,
    ) => Effect.Effect<NoteReaction, NotesNotFound | InvalidNote | NotesUnavailable>;
    readonly list: (
      userId: UserId,
      afterRev: number,
      limit: number,
    ) => Effect.Effect<ReadonlyArray<NoteReaction>, NotesNotFound | NotesUnavailable>;
  }
>()("@billet/backend-notes/ReactionService") {
  static readonly layer: Layer.Layer<ReactionService, never, PairingRepository | PairRooms> =
    Layer.effect(
      ReactionService,
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

        const react = Effect.fn("ReactionService.react")(function* (
          userId: UserId,
          request: ReactRequest,
        ): Effect.fn.Return<NoteReaction, NotesNotFound | InvalidNote | NotesUnavailable> {
          const decision = yield* rooms.react(yield* pairOf(userId), userId, request);
          if (decision._tag === "Rejected") {
            switch (decision.rejection._tag) {
              // No room yet means no photo yet.
              case "RoomNotOpen":
              case "NoteNotFound":
              case "NoReaction":
                return yield* Effect.fail(new NotesNotFound());
              case "OwnNote":
              case "NotReactable":
                return yield* Effect.fail(new InvalidNote());
              case "NotAMember":
              case "DuplicateMember":
              case "RoomAlreadyOpen":
              case "CatNotAdopted":
              case "CatEntryIdTaken":
              case "InkNotOwned":
              case "NotEnoughCoins":
              case "AlreadyOwned":
              case "NotSold":
              case "OfferOwned":
              case "NotOffered":
              case "GiftTaken":
              case "CollectionIncomplete":
              case "BonusTaken":
              case "ListNotFound":
              case "ListItemNotFound":
              case "MoodNoteTooLong":
                return yield* Effect.fail(
                  new NotesUnavailable({ reason: "room-refused-reaction" }),
                );
            }
          }
          const reaction = decision.outputs.flatMap((output) =>
            output._tag === "ReactionSet" || output._tag === "ReactionRepeated"
              ? [output.reaction]
              : [],
          )[0];
          if (reaction === undefined) {
            return yield* Effect.fail(new NotesUnavailable({ reason: "reaction-not-set" }));
          }
          return reaction;
        });

        const list = Effect.fn("ReactionService.list")(function* (
          userId: UserId,
          afterRev: number,
          limit: number,
        ) {
          return yield* rooms.reactions(yield* pairOf(userId), afterRev, limit);
        });

        return ReactionService.of({ react, list });
      }),
    );
}
