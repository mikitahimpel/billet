import { Effect, Layer } from "effect";
import type { RoomJoin } from "@billet/backend-pair-room/room-command";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { DemoPartnerRepository } from "@billet/backend-demo-partner/demo-partner-repository";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { Metrics } from "@billet/backend-metrics/metrics";
import { PairRooms } from "@billet/backend-notes/pair-rooms";
import { PairingObserver } from "@billet/backend-pairing/pairing-observer";
import { spanMethods } from "@billet/backend-observability/span-methods";

/**
 * What the Worker does when pairing succeeds: gives the new pair its experiment variants (if that
 * fails, the first read of the flags does it) and counts the funnel steps, and opens the pair's room with who joined. When a pair ends, it
 * closes the room's open sockets, which the directory no longer lets reconnect.
 */
export const PairingObserverLive: Layer.Layer<
  PairingObserver,
  never,
  FlagsService | Metrics | PairRooms | DemoPartnerRepository
> = Layer.effect(
  PairingObserver,
  Effect.gen(function* () {
    const flags = yield* FlagsService;
    const metrics = yield* Metrics;
    const rooms = yield* PairRooms;
    const demos = yield* DemoPartnerRepository;
    // A demo partner is a test fixture, not a person: its invite isn't counted, and its pair is
    // kept under its own name, out of the funnel. If the lookup fails, it counts as a person.
    const withBot = (users: ReadonlyArray<UserId>) =>
      Effect.forEach(users, (userId) => demos.isBot(userId)).pipe(
        Effect.map((bots) => bots.includes(true)),
        Effect.catchCause(() => Effect.succeed(false)),
      );
    // The pair's first Inbox item: the room opens now, with who joined, instead of on first use.
    // If this fails, the first note or look at the cat opens it, without that item.
    const openRoom = (pairId: PairId, members: ReadonlyArray<UserId>, joined: RoomJoin) => {
      const [first, second] = members;
      return first === undefined || second === undefined
        ? Effect.void
        : rooms.open(pairId, [first, second], joined).pipe(Effect.ignore);
    };
    return PairingObserver.of(
      spanMethods("PairingObserver", {
        invited: (userId) =>
          withBot([userId]).pipe(
            Effect.flatMap((bot) =>
              bot ? Effect.void : metrics.record({ userId, name: "InviteCreated" }),
            ),
          ),
        paired: (pairId, members, { claimer, at }) =>
          Effect.all(
            [
              flags.assignPair(pairId).pipe(Effect.ignore),
              openRoom(pairId, members, { user: claimer, at }),
              withBot(members).pipe(
                Effect.flatMap((bot) =>
                  Effect.forEach(
                    members,
                    (userId) =>
                      metrics.record({
                        userId,
                        pairId,
                        name: bot ? "DemoPairClaimed" : "PairClaimed",
                      }),
                    { discard: true },
                  ),
                ),
              ),
            ],
            { discard: true },
          ),
        unpaired: (pairId) => rooms.endSessions(pairId).pipe(Effect.orDie),
      }),
    );
  }),
);
