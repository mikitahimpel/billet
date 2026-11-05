import { Context, Effect, Layer, Option } from "effect";
import type { ActivityCursor } from "@billet/contracts-domain/activity";
import type { UserId } from "@billet/contracts-domain/ids";
import type { ActivityResponse } from "@billet/contracts-http-api/activity";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { NotesNotFound, NotesUnavailable } from "./notes-error.ts";
import { PairRooms } from "./pair-rooms.ts";

const directoryUnavailable = () => new NotesUnavailable({ reason: "directory-unavailable" });

/**
 * The pair's activity Inbox, for the caller's own pair: the pair comes from D1, never from the
 * client. See docs/activity.md.
 */
export class ActivityService extends Context.Service<
  ActivityService,
  {
    readonly list: (
      userId: UserId,
      before: ActivityCursor | undefined,
      limit: number,
    ) => Effect.Effect<ActivityResponse, NotesNotFound | NotesUnavailable>;
    /** Marks the caller's items read up to `upTo` and answers their unread count. */
    readonly markRead: (
      userId: UserId,
      upTo: ActivityCursor,
    ) => Effect.Effect<number, NotesNotFound | NotesUnavailable>;
  }
>()("@billet/backend-notes/ActivityService") {
  static readonly layer: Layer.Layer<ActivityService, never, PairingRepository | PairRooms> =
    Layer.effect(
      ActivityService,
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

        const list = Effect.fn("ActivityService.list")(function* (
          userId: UserId,
          before: ActivityCursor | undefined,
          limit: number,
        ) {
          return yield* rooms.activity(yield* pairOf(userId), userId, before, limit);
        });

        const markRead = Effect.fn("ActivityService.markRead")(function* (
          userId: UserId,
          upTo: ActivityCursor,
        ) {
          return yield* rooms.markActivityRead(yield* pairOf(userId), userId, upTo);
        });

        return ActivityService.of({ list, markRead });
      }),
    );
}
