import { Clock, Context, Duration, Effect, Layer, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import {
  InviteCode,
  inviteCodeAlphabet,
  inviteCodeLength,
  type UserId,
} from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { CreateInviteResponse } from "@billet/contracts-http-api/invite";
import type { AlreadyPaired, InvalidInvite, PairingUnavailable } from "./pairing-error.ts";
import { PairingRepository } from "./pairing-repository.ts";

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
  }
>()("@billet/backend-pairing/PairingService") {
  static readonly layer: Layer.Layer<
    PairingService,
    never,
    PairingRepository | Digest.Digest | SecureRandom.SecureRandom
  > = Layer.effect(
    PairingService,
    Effect.gen(function* () {
      const repository = yield* PairingRepository;
      const digest = yield* Digest.Digest;
      const random = yield* SecureRandom.SecureRandom;

      const hash = (code: InviteCode) => digest.digestHex(Digest.sha256, encoder.encode(code));

      // The alphabet has 32 symbols, so masking a random byte to 5 bits picks one without bias.
      const newCode = Effect.map(random.randomBytes(inviteCodeLength), (bytes) =>
        decodeInviteCode(Array.from(bytes, (byte) => inviteCodeAlphabet[byte & 31]).join("")),
      );

      const createInvite = Effect.fnUntraced(function* (
        ownerId: UserId,
      ): Effect.fn.Return<CreateInviteResponse, AlreadyPaired | PairingUnavailable> {
        const code = yield* newCode;
        const createdAt = yield* Clock.currentTimeMillis;
        const expiresAt = createdAt + Duration.toMillis(inviteLifetime);
        yield* repository.saveInvite({
          codeHash: yield* hash(code),
          ownerId,
          createdAt,
          expiresAt,
        });
        return { code, expiresAt };
      });

      const claimInvite = Effect.fnUntraced(function* (
        claimerId: UserId,
        code: InviteCode,
      ): Effect.fn.Return<PairId, InvalidInvite | AlreadyPaired | PairingUnavailable> {
        const pairId = decodePairId(yield* random.uuidV4());
        yield* repository.claimInvite({
          codeHash: yield* hash(code),
          claimerId,
          pairId,
          now: yield* Clock.currentTimeMillis,
        });
        return pairId;
      });

      return PairingService.of({ createInvite, claimInvite, unpair: repository.unpair });
    }),
  );
}
