import { Clock, Context, Effect, Layer, Option, Schema } from "effect";
import { SecureRandom } from "effect/crypto";
import { AccountDeletion } from "@billet/backend-account/account-deletion";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { AlreadyPaired } from "@billet/backend-pairing/pairing-error";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import { UserId } from "@billet/contracts-domain/ids";
import type { DemoPartnerResponse, PairResponse } from "@billet/contracts-http-api/pair";
import { DemoPartnerUnavailable, NoDemoPartner } from "./demo-partner-error.ts";
import { DemoBots } from "./demo-bots.ts";
import { DemoPartnerRepository } from "./demo-partner-repository.ts";

const decodeUserId = Schema.decodeSync(UserId);

const unavailable =
  (reason: string) =>
  (cause: unknown): DemoPartnerUnavailable =>
    new DemoPartnerUnavailable({ reason, cause });

/**
 * A dev-stage partner for testing alone: a user with no device, paired by invite like anyone.
 */
export class DemoPartnerService extends Context.Service<
  DemoPartnerService,
  {
    /** Pairs the caller with a new bot. The caller's pair, the caller first. */
    readonly create: (
      ownerId: UserId,
    ) => Effect.Effect<PairResponse, AlreadyPaired | DemoPartnerUnavailable>;
    /** Whether the caller is paired with their bot. */
    readonly status: (
      ownerId: UserId,
    ) => Effect.Effect<DemoPartnerResponse, DemoPartnerUnavailable>;
    /** Unpairs the caller from their bot if they are paired with it, then deletes the bot. */
    readonly remove: (
      ownerId: UserId,
    ) => Effect.Effect<void, NoDemoPartner | DemoPartnerUnavailable>;
  }
>()("@billet/backend-demo-partner/DemoPartnerService") {
  static readonly layer: Layer.Layer<
    DemoPartnerService,
    never,
    DemoPartnerRepository | DemoBots | PairingService | AccountDeletion | SecureRandom.SecureRandom
  > = Layer.effect(
    DemoPartnerService,
    Effect.gen(function* () {
      const repository = yield* DemoPartnerRepository;
      const pairing = yield* PairingService;
      const deletion = yield* AccountDeletion;
      const random = yield* SecureRandom.SecureRandom;
      const bots = yield* DemoBots;

      const pairOf = (userId: UserId) =>
        pairing.pair(userId).pipe(
          Effect.map(Option.some),
          Effect.catchTag("NotPaired", () => Effect.succeed(Option.none<PairResponse>())),
          Effect.mapError(unavailable("pairing-unavailable")),
        );

      const erase = (botId: UserId) =>
        deletion
          .deleteAccount(botId, Option.none())
          .pipe(
            Effect.mapError(unavailable("account-unavailable")),
            Effect.andThen(repository.forget(botId)),
          );

      const create = Effect.fn("DemoPartnerService.create")(function* (
        ownerId: UserId,
      ): Effect.fn.Return<PairResponse, AlreadyPaired | DemoPartnerUnavailable> {
        yield* annotateRefs({ user: ownerId });
        if (Option.isSome(yield* pairOf(ownerId))) return yield* new AlreadyPaired();

        // A bot the owner was unpaired from some other way: one owner has one bot.
        const stale = yield* repository.botOf(ownerId);
        if (Option.isSome(stale)) yield* erase(stale.value);

        const botId = decodeUserId(yield* random.uuidV4());
        yield* repository.create({ botId, ownerId, createdAt: yield* Clock.currentTimeMillis });
        const pairId = yield* pairing.createInvite(botId).pipe(
          Effect.flatMap(({ code }) => pairing.claimInvite(ownerId, code)),
          Effect.catchTags({
            InvalidInvite: (error) => Effect.fail(unavailable("invite-refused")(error)),
            PairingUnavailable: (error) => Effect.fail(unavailable("pairing-unavailable")(error)),
          }),
          // The owner paired with someone else in the meantime, so the bot has no one.
          Effect.tapError(() => erase(botId).pipe(Effect.ignore)),
        );
        // A bot that never wakes is still a partner to pair with, so this does not fail the pair.
        yield* bots
          .start(pairId, ownerId, botId)
          .pipe(Effect.catch((error) => Effect.logWarning("demo bot not started", error)));
        return { pairId, members: [ownerId, botId], moods: [] };
      });

      const remove = Effect.fn("DemoPartnerService.remove")(function* (
        ownerId: UserId,
      ): Effect.fn.Return<void, NoDemoPartner | DemoPartnerUnavailable> {
        yield* annotateRefs({ user: ownerId });
        const bot = yield* repository.botOf(ownerId);
        if (Option.isNone(bot)) return yield* new NoDemoPartner();
        const pair = yield* pairOf(ownerId);
        // First, so deleting the bot leaves the owner no notice that their partner left.
        if (Option.isSome(pair) && pair.value.members[1] === bot.value) {
          yield* bots.stop(pair.value.pairId);
          yield* pairing.unpair(ownerId).pipe(Effect.mapError(unavailable("pairing-unavailable")));
        }
        yield* erase(bot.value);
      });

      const status = Effect.fn("DemoPartnerService.status")(function* (
        ownerId: UserId,
      ): Effect.fn.Return<DemoPartnerResponse, DemoPartnerUnavailable> {
        const bot = yield* repository.botOf(ownerId);
        if (Option.isNone(bot)) return { paired: false };
        const pair = yield* pairOf(ownerId);
        return { paired: Option.isSome(pair) && pair.value.members[1] === bot.value };
      });

      return DemoPartnerService.of({ create, status, remove });
    }),
  );
}
