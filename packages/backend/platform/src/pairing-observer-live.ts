import { Effect, Layer } from "effect";
import { freeInk, InkId } from "@billet/contracts-domain/inks";
import { RoomItemId, starterItems } from "@billet/contracts-domain/shop";
import { CoinEntryId } from "@billet/contracts-domain/coins";
import { Schema } from "effect";
import type { RoomJoin } from "@billet/backend-pair-room/room-command";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { DemoPartnerRepository } from "@billet/backend-demo-partner/demo-partner-repository";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { Metrics } from "@billet/backend-metrics/metrics";
import { MediaStore } from "@billet/backend-notes/media-store";
import { PairRooms } from "@billet/backend-notes/pair-rooms";
import { mergeKept, splitKept } from "@billet/backend-pairing/kept-purchases";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { PairingObserver } from "@billet/backend-pairing/pairing-observer";
import { ReviewRepository } from "@billet/backend-review/review-repository";
import { spanMethods } from "@billet/backend-observability/span-methods";

const decodeInk = Schema.decodeSync(InkId);
const decodeItem = Schema.decodeSync(RoomItemId);
const decodeEntryId = Schema.decodeSync(CoinEntryId);

/**
 * What the Worker does when pairing succeeds: gives the new pair its experiment variants (if that
 * fails, the first read of the flags does it) and counts the funnel steps, and opens the pair's room with who joined. When a pair ends, each
 * partner keeps their share of the purchases, then the room's sockets close and the room and the
 * pair's images are deleted. A pair that forms gives its room what its members keep.
 */
export const PairingObserverLive: Layer.Layer<
  PairingObserver,
  never,
  | FlagsService
  | Metrics
  | PairRooms
  | MediaStore
  | PairingRepository
  | DemoPartnerRepository
  | ReviewRepository
> = Layer.effect(
  PairingObserver,
  Effect.gen(function* () {
    const flags = yield* FlagsService;
    const metrics = yield* Metrics;
    const rooms = yield* PairRooms;
    const media = yield* MediaStore;
    const demos = yield* DemoPartnerRepository;
    const review = yield* ReviewRepository;
    const pairing = yield* PairingRepository;
    // A demo partner or the App Review partner is a fixture, not a person: its invite isn't
    // counted, and its pair is kept under its own name, out of the funnel. If the lookup fails, it
    // counts as a person.
    const withBot = (users: ReadonlyArray<UserId>) =>
      Effect.forEach(users, (userId) =>
        Effect.zipWith(
          demos.isBot(userId),
          review.isPartner(userId),
          (bot, partner) => bot || partner,
        ),
      ).pipe(
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
    const isBot = (userId: UserId) =>
      demos.isBot(userId).pipe(Effect.catchCause(() => Effect.succeed(false)));

    // Purchases are never deleted: before the room goes, each partner keeps their share.
    const keepPurchases = Effect.fn("PairingObserver.keepPurchases")(function* (
      pairId: PairId,
      members: ReadonlyArray<UserId>,
    ) {
      const shop = yield* rooms.shop(pairId);
      if (shop === null) return;
      const people = yield* Effect.filter(members, (userId) =>
        Effect.map(isBot(userId), (b) => !b),
      );
      const kept = splitKept(people, {
        coins: shop.balance,
        inks: shop.inks.filter((ink) => ink !== freeInk),
        items: shop.items.filter((item) => !starterItems.includes(item)),
      });
      yield* Effect.forEach(kept, ([userId, purchases]) => pairing.keep(userId, purchases), {
        discard: true,
      });
    });

    // The new pair's room is given what its members keep; the rows go once the room has it.
    const restorePurchases = Effect.fn("PairingObserver.restorePurchases")(function* (
      pairId: PairId,
      members: ReadonlyArray<UserId>,
    ) {
      const kept = yield* Effect.forEach(members, (userId) => pairing.kept(userId));
      const all = mergeKept(kept);
      if (all.inks.length > 0)
        yield* rooms.grantInks(
          pairId,
          all.inks.map((ink) => decodeInk(ink)),
        );
      if (all.items.length > 0)
        yield* rooms.grantItems(
          pairId,
          all.items.map((item) => decodeItem(item)),
        );
      if (all.coins > 0) {
        yield* rooms.creditPurchase(pairId, {
          kind: "buy",
          id: decodeEntryId(`buy:kept-${pairId}`),
          ref: "kept",
          coins: all.coins,
        });
      }
      yield* Effect.forEach(members, (userId) => pairing.clearKept(userId), { discard: true });
    });

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
              restorePurchases(pairId, members).pipe(Effect.ignore),
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
        unpaired: (pairId, members) =>
          keepPurchases(pairId, members).pipe(
            Effect.andThen(Effect.all([rooms.destroy(pairId), media.removeAll(pairId)])),
            Effect.asVoid,
            Effect.orDie,
          ),
      }),
    );
  }),
);
