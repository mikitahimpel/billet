import { Clock, Context, Duration, Effect, Layer, Option, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import {
  InviteCode,
  inviteCodeAlphabet,
  inviteCodeLength,
  type UserId,
} from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { CreateInviteResponse } from "@billet/contracts-http-api/invite";
import type { PairResponse } from "@billet/contracts-http-api/pair";
import type { ReportPartnerRequest } from "@billet/contracts-http-api/safety";
import {
  type AlreadyPaired,
  type InvalidInvite,
  NotPaired,
  type PairingUnavailable,
} from "./pairing-error.ts";
import { PairMoods } from "./pair-moods.ts";
import { PairingObserver } from "./pairing-observer.ts";
import { PairingRepository } from "./pairing-repository.ts";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";

/** Long enough to send a code to someone who is asleep, short enough that a leaked one goes stale. */
export const inviteLifetime = Duration.hours(24);

const decodeInviteCode = Schema.decodeSync(InviteCode);
const decodePairId = Schema.decodeSync(PairId);

const encoder = new TextEncoder();

/** Invites and the pair lookup go through here; routes never see the repository. */
export class PairingService extends Context.Service<
  PairingService,
  {
    /** Issues a new code, which replaces the caller's earlier one. */
    readonly createInvite: (
      userId: UserId,
    ) => Effect.Effect<CreateInviteResponse, AlreadyPaired | PairingUnavailable>;
    readonly claimInvite: (
      userId: UserId,
      code: InviteCode,
    ) => Effect.Effect<PairId, InvalidInvite | AlreadyPaired | PairingUnavailable>;
    readonly unpair: (userId: UserId) => Effect.Effect<void, PairingUnavailable>;
    /** Unpairs the caller from their partner for good: the two can't pair again. */
    readonly blockPartner: (userId: UserId) => Effect.Effect<void, NotPaired | PairingUnavailable>;
    /** Keeps a report about the caller's partner for the team. The pair stays. */
    readonly reportPartner: (
      userId: UserId,
      request: ReportPartnerRequest,
    ) => Effect.Effect<void, NotPaired | PairingUnavailable>;
    /** The caller's pair and both members, the caller first, with their latest check-ins. */
    readonly pair: (userId: UserId) => Effect.Effect<PairResponse, NotPaired | PairingUnavailable>;
  }
>()("@billet/backend-pairing/PairingService") {
  static readonly layer: Layer.Layer<
    PairingService,
    never,
    PairingRepository | PairingObserver | PairMoods | Digest.Digest | SecureRandom.SecureRandom
  > = Layer.effect(
    PairingService,
    Effect.gen(function* () {
      const repository = yield* PairingRepository;
      const observer = yield* PairingObserver;
      const moods = yield* PairMoods;
      const digest = yield* Digest.Digest;
      const random = yield* SecureRandom.SecureRandom;

      // Side effects of a committed pairing: a failure is logged and never undoes or fails it.
      const afterwards = (effect: Effect.Effect<void>) =>
        effect.pipe(Effect.catchCause(() => Effect.logWarning("pairing follow-up failed")));

      const hash = (code: InviteCode) => digest.digestHex(Digest.sha256, encoder.encode(code));

      // The alphabet has 32 symbols, so masking a random byte to 5 bits picks one without bias.
      const newCode = Effect.map(random.randomBytes(inviteCodeLength), (bytes) =>
        decodeInviteCode(Array.from(bytes, (byte) => inviteCodeAlphabet[byte & 31]).join("")),
      );

      const createInvite = Effect.fn("PairingService.createInvite")(function* (
        ownerId: UserId,
      ): Effect.fn.Return<CreateInviteResponse, AlreadyPaired | PairingUnavailable> {
        yield* annotateRefs({ user: ownerId });
        const code = yield* newCode;
        const createdAt = yield* Clock.currentTimeMillis;
        const expiresAt = createdAt + Duration.toMillis(inviteLifetime);
        yield* repository.saveInvite({
          codeHash: yield* hash(code),
          ownerId,
          createdAt,
          expiresAt,
        });
        yield* afterwards(observer.invited(ownerId));
        return { code, expiresAt };
      });

      const claimInvite = Effect.fn("PairingService.claimInvite")(function* (
        claimerId: UserId,
        code: InviteCode,
      ): Effect.fn.Return<PairId, InvalidInvite | AlreadyPaired | PairingUnavailable> {
        const pairId = decodePairId(yield* random.uuidV4());
        yield* annotateRefs({ user: claimerId, pair: pairId });
        const now = yield* Clock.currentTimeMillis;
        yield* repository.claimInvite({ codeHash: yield* hash(code), claimerId, pairId, now });
        yield* afterwards(
          repository.findMembers(pairId).pipe(
            Effect.orDie,
            Effect.flatMap((members) =>
              observer.paired(pairId, members, { claimer: claimerId, at: now }),
            ),
          ),
        );
        return pairId;
      });

      const pair = Effect.fn("PairingService.pair")(function* (
        userId: UserId,
      ): Effect.fn.Return<PairResponse, NotPaired | PairingUnavailable> {
        const found = yield* repository.findPair(userId);
        if (Option.isNone(found)) return yield* Effect.fail(new NotPaired());
        const pairId = found.value;
        const partner = (yield* repository.findMembers(pairId)).find((member) => member !== userId);
        // The pair ended between the two reads.
        if (partner === undefined) return yield* Effect.fail(new NotPaired());
        return { pairId, members: [userId, partner], moods: yield* moods.latest(pairId) };
      });

      const unpair = Effect.fn("PairingService.unpair")(function* (
        userId: UserId,
      ): Effect.fn.Return<void, PairingUnavailable> {
        const pair = yield* repository.findPair(userId);
        yield* repository.unpair(userId);
        if (Option.isSome(pair)) yield* afterwards(observer.unpaired(pair.value));
      });

      const partnerOf = Effect.fn("PairingService.partnerOf")(function* (
        userId: UserId,
      ): Effect.fn.Return<{ pairId: PairId; partner: UserId }, NotPaired | PairingUnavailable> {
        const found = yield* repository.findPair(userId);
        if (Option.isNone(found)) return yield* Effect.fail(new NotPaired());
        const partner = (yield* repository.findMembers(found.value)).find(
          (member) => member !== userId,
        );
        if (partner === undefined) return yield* Effect.fail(new NotPaired());
        return { pairId: found.value, partner };
      });

      const blockPartner = Effect.fn("PairingService.blockPartner")(function* (
        userId: UserId,
      ): Effect.fn.Return<void, NotPaired | PairingUnavailable> {
        const { pairId, partner } = yield* partnerOf(userId);
        yield* repository.block({
          blocker: userId,
          blocked: partner,
          at: yield* Clock.currentTimeMillis,
        });
        yield* afterwards(observer.unpaired(pairId));
      });

      const reportPartner = Effect.fn("PairingService.reportPartner")(function* (
        userId: UserId,
        request: ReportPartnerRequest,
      ): Effect.fn.Return<void, NotPaired | PairingUnavailable> {
        const { pairId, partner } = yield* partnerOf(userId);
        yield* repository.saveReport({
          id: yield* random.uuidV4(),
          reporter: userId,
          reported: partner,
          pairId,
          reason: request.reason,
          details: request.details,
          at: yield* Clock.currentTimeMillis,
        });
      });

      return PairingService.of({
        createInvite,
        claimInvite,
        unpair,
        blockPartner,
        reportPartner,
        pair,
      });
    }),
  );
}
