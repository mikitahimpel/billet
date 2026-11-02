import { Clock, Context, Duration, Effect, Layer, Option, Redacted, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { Base64Url } from "effect/encoding";
import { DeviceId, type EpochMillis, UserId } from "@billet/contracts-domain/ids";
import {
  AuthNonce,
  SessionToken,
  type AuthChallengeResponse,
  type SessionResponse,
} from "@billet/contracts-http-api/auth";
import type { RegisterPushTokenRequest } from "@billet/contracts-http-api/device";
import { AuthRejected, type AuthUnavailable } from "./auth-error.ts";
import { AuthRepository, type TokenHash } from "./auth-repository.ts";
import { IdentityVerifier } from "./identity-verifier.ts";

/** Long enough to fetch a nonce, show the Apple sheet and post the result. */
export const challengeLifetime = Duration.minutes(10);
/**
 * Sliding: widgets and extensions can't show the Apple sheet, so an active device stays signed in
 * and one idle this long signs in again.
 */
export const sessionLifetime = Duration.days(90);
/** Limits writes to one per session per day. */
const sessionRenewalInterval = Duration.days(1);

const opaqueBytes = 32;

export interface Principal {
  readonly userId: UserId;
  readonly deviceId: DeviceId;
  readonly sessionHash: TokenHash;
}

const decodeUserId = Schema.decodeSync(UserId);
const decodeDeviceId = Schema.decodeSync(DeviceId);
const decodeNonce = Schema.decodeSync(AuthNonce);
const decodeSessionToken = Schema.decodeSync(SessionToken);
const isSessionToken = Schema.is(SessionToken);

const encoder = new TextEncoder();

/** Sessions and identity go through here; routes never see the repository. */
export class AuthService extends Context.Service<
  AuthService,
  {
    readonly issueChallenge: Effect.Effect<AuthChallengeResponse, AuthUnavailable>;
    readonly signInWithApple: (
      identityToken: Redacted.Redacted<string>,
    ) => Effect.Effect<SessionResponse, AuthRejected | AuthUnavailable>;
    readonly authenticate: (
      sessionToken: Redacted.Redacted<string>,
    ) => Effect.Effect<Principal, AuthRejected | AuthUnavailable>;
    readonly signOut: (principal: Principal) => Effect.Effect<void, AuthUnavailable>;
    readonly registerPushToken: (
      principal: Principal,
      request: RegisterPushTokenRequest,
    ) => Effect.Effect<void, AuthUnavailable>;
  }
>()("@billet/backend-auth/AuthService") {
  static readonly layer: Layer.Layer<
    AuthService,
    never,
    AuthRepository | IdentityVerifier | Digest.Digest | SecureRandom.SecureRandom
  > = Layer.effect(
    AuthService,
    Effect.gen(function* () {
      const repository = yield* AuthRepository;
      const verifier = yield* IdentityVerifier;
      const digest = yield* Digest.Digest;
      const random = yield* SecureRandom.SecureRandom;

      /**
       * Plain SHA-256 is right here: the input is 256 random bits, so there is nothing to guess and
       * a slow hash or salt adds no protection. Lookups go through this hash, so an attacker can't
       * steer a comparison byte by byte; no code here compares a secret directly.
       */
      const hash = (value: string): Effect.Effect<TokenHash> =>
        digest.digestHex(Digest.sha256, encoder.encode(value));

      const opaqueValue = Effect.map(random.randomBytes(opaqueBytes), Base64Url.encode);

      const expiryFrom = (now: EpochMillis, lifetime: Duration.Duration): EpochMillis =>
        now + Duration.toMillis(lifetime);

      const issueChallenge = Effect.gen(function* () {
        const nonce = decodeNonce(yield* opaqueValue);
        const expiresAt = expiryFrom(yield* Clock.currentTimeMillis, challengeLifetime);
        yield* repository.saveChallenge(yield* hash(nonce), expiresAt);
        return { nonce, expiresAt };
      });

      const signInWithApple = Effect.fnUntraced(function* (
        identityToken: Redacted.Redacted<string>,
      ): Effect.fn.Return<SessionResponse, AuthRejected | AuthUnavailable> {
        const identity = yield* verifier.verify(identityToken);
        const now = yield* Clock.currentTimeMillis;
        // Only after the signature checks out, so forged tokens can't burn someone's nonce.
        const fresh = yield* repository.consumeChallenge(yield* hash(identity.nonce), now);
        if (!fresh) return yield* new AuthRejected({ reason: "nonce-not-live" });

        const sessionToken = decodeSessionToken(yield* opaqueValue);
        const deviceId = decodeDeviceId(yield* random.uuidV4());
        const expiresAt = expiryFrom(now, sessionLifetime);
        const userId = yield* repository.createSession({
          appleSubject: identity.subject,
          candidateUserId: decodeUserId(yield* random.uuidV4()),
          deviceId,
          sessionHash: yield* hash(sessionToken),
          createdAt: now,
          expiresAt,
        });
        // Housekeeping must not cost a user a sign-in that already succeeded.
        yield* repository.deleteExpired(now).pipe(Effect.ignore);
        return { sessionToken, expiresAt, userId, deviceId };
      });

      const authenticate = Effect.fnUntraced(function* (
        sessionToken: Redacted.Redacted<string>,
      ): Effect.fn.Return<Principal, AuthRejected | AuthUnavailable> {
        const raw = Redacted.value(sessionToken);
        if (!isSessionToken(raw)) return yield* new AuthRejected({ reason: "session-malformed" });

        const sessionHash = yield* hash(raw);
        const now = yield* Clock.currentTimeMillis;
        const session = yield* repository.findSession(sessionHash, now);
        if (Option.isNone(session)) return yield* new AuthRejected({ reason: "session-not-live" });

        const renewed = expiryFrom(now, sessionLifetime);
        if (renewed - session.value.expiresAt >= Duration.toMillis(sessionRenewalInterval)) {
          yield* repository.extendSession(sessionHash, renewed);
        }
        const { userId, deviceId } = session.value;
        return { userId, deviceId, sessionHash };
      });

      const registerPushToken = Effect.fnUntraced(function* (
        principal: Principal,
        request: RegisterPushTokenRequest,
      ): Effect.fn.Return<void, AuthUnavailable> {
        yield* repository.savePushToken(principal.deviceId, {
          ...request,
          updatedAt: yield* Clock.currentTimeMillis,
        });
      });

      return AuthService.of({
        issueChallenge,
        signInWithApple,
        authenticate,
        signOut: (principal) => repository.revokeSession(principal.sessionHash),
        registerPushToken,
      });
    }),
  );
}
