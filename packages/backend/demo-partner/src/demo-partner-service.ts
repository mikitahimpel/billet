import { Clock, Context, Effect, Layer, Option, Schema } from "effect";
import { SecureRandom } from "effect/crypto";
import { AccountDeletion } from "@billet/backend-account/account-deletion";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { AlreadyPaired } from "@billet/backend-pairing/pairing-error";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import { UserId } from "@billet/contracts-domain/ids";
import type { PairResponse } from "@billet/contracts-http-api/pair";
import { DemoPartnerUnavailable, NoDemoPartner } from "./demo-partner-error.ts";
import { DemoPartnerRepository } from "./demo-partner-repository.ts";

const decodeUserId = Schema.decodeSync(UserId);

const unavailable =
  (reason: string) =>
  (cause: unknown): DemoPartnerUnavailable =>
    new DemoPartnerUnavailable({ reason, cause });

/**
 * A partner for testing the app alone, on the dev stage: a user with no device and no way to sign
 * in, paired with its owner through an invite like anyone else, so everything a new pair gets, it
 * gets too.
 */
export class DemoPartnerService extends Context.Service<
  DemoPartnerService,
  {
    /** Pairs the caller with a new bot. The caller's pair, the caller first. */
    readonly create: (
      ownerId: UserId,
    ) => Effect.Effect<PairResponse, AlreadyPaired | DemoPartnerUnavailable>;
    /** Unpairs the caller from their bot if they are paired with it, then deletes the bot. */
    readonly remove: (
      ownerId: UserId,
    ) => Effect.Effect<void, NoDemoPartner | DemoPartnerUnavailable>;
  }
>()("@billet/backend-demo-partner/DemoPartnerService") {
  static readonly layer: Layer.Layer<
    DemoPartnerService,
    never,
    DemoPartnerRepository | PairingService | AccountDeletion | SecureRandom.SecureRandom
  > = Layer.effect(
    DemoPartnerService,
    Effect.gen(function* () {
      const repository = yield* DemoPartnerRepository;
      const pairing = yield* PairingService;
      const deletion = yield* AccountDeletion;
      const random = yield* SecureRandom.SecureRandom;

      const partnerOf = (userId: UserId) =>
        pairing.pair(userId).pipe(
          Effect.map(({ members }) => Option.fromNullishOr(members[1])),
          Effect.catchTag("NotPaired", () => Effect.succeed(Option.none<UserId>())),
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
        if (Option.isSome(yield* partnerOf(ownerId))) return yield* new AlreadyPaired();

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
        return { pairId, members: [ownerId, botId] };
      });

      const remove = Effect.fn("DemoPartnerService.remove")(function* (
        ownerId: UserId,
      ): Effect.fn.Return<void, NoDemoPartner | DemoPartnerUnavailable> {
        yield* annotateRefs({ user: ownerId });
        const bot = yield* repository.botOf(ownerId);
        if (Option.isNone(bot)) return yield* new NoDemoPartner();
        const partner = yield* partnerOf(ownerId);
        // First, so deleting the bot leaves the owner no notice that their partner left.
        if (Option.contains(partner, bot.value)) {
          yield* pairing.unpair(ownerId).pipe(Effect.mapError(unavailable("pairing-unavailable")));
        }
        yield* erase(bot.value);
      });

      return DemoPartnerService.of({ create, remove });
    }),
  );
}
