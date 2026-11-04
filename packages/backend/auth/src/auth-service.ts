import { Clock, Context, Duration, Effect, Layer, Option, Redacted, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { Base64Url } from "effect/encoding";
import type { DeviceId, EpochMillis, UserId } from "@billet/contracts-domain/ids";
import {
  AccountKey,
  AuthNonce,
  SessionToken,
  type AuthChallengeResponse,
  type SessionResponse,
} from "@billet/contracts-http-api/auth";
import type { AccountResponse } from "@billet/contracts-http-api/account";
import type { RegisterPushTokenRequest } from "@billet/contracts-http-api/device";
import { AccountNotices } from "./account-notices.ts";
import { AppleIdInUse, AuthRejected, type AuthUnavailable } from "./auth-error.ts";
import { AuthEngine, type IssuedSession, type VerifiedApple } from "./auth-engine.ts";
import { AuthRepository, type TokenHash } from "./auth-repository.ts";
import { IdentityVerifier } from "./identity-verifier.ts";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";

/** Long enough to fetch a nonce, show the Apple sheet and post the result. */
export const challengeLifetime = Duration.minutes(10);
/**
 * Sliding: widgets and extensions can't show a prompt, so an active device stays signed in and one
 * idle this long signs in again, with its account key or Apple ID.
 */
export const sessionLifetime = Duration.days(90);
/** Limits writes to one per session per day. */
export const sessionRenewalInterval = Duration.days(1);

const opaqueBytes = 32;

export interface Principal {
  readonly userId: UserId;
  readonly deviceId: DeviceId;
  readonly sessionHash: TokenHash;
}

const decodeNonce = Schema.decodeSync(AuthNonce);
const isSessionToken = Schema.is(SessionToken);
const isAccountKey = Schema.is(AccountKey);

const encoder = new TextEncoder();

const toResponse = (session: IssuedSession): SessionResponse => ({
  sessionToken: session.sessionToken,
  expiresAt: session.expiresAt,
  userId: session.userId,
  deviceId: session.deviceId,
});

/** Sessions and identity go through here; routes never see the repository or the engine. */
export class AuthService extends Context.Service<
  AuthService,
  {
    readonly issueChallenge: Effect.Effect<AuthChallengeResponse, AuthUnavailable>;
    /** Signs in to the account this key opened, opening one the first time the key is seen. */
    readonly signInAnonymously: (
      accountKey: Redacted.Redacted<string>,
    ) => Effect.Effect<SessionResponse, AuthRejected | AuthUnavailable>;
    readonly signInWithApple: (
      identityToken: Redacted.Redacted<string>,
    ) => Effect.Effect<SessionResponse, AuthRejected | AuthUnavailable>;
    /** Links the caller's account to the Apple ID in the token. */
    readonly linkApple: (
      sessionToken: Redacted.Redacted<string>,
      identityToken: Redacted.Redacted<string>,
    ) => Effect.Effect<AccountResponse, AppleIdInUse | AuthRejected | AuthUnavailable>;
    readonly authenticate: (
      sessionToken: Redacted.Redacted<string>,
    ) => Effect.Effect<Principal, AuthRejected | AuthUnavailable>;
    readonly account: (
      sessionToken: Redacted.Redacted<string>,
    ) => Effect.Effect<AccountResponse, AuthRejected | AuthUnavailable>;
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
    | AccountNotices
    | AuthEngine
    | AuthRepository
    | IdentityVerifier
    | Digest.Digest
    | SecureRandom.SecureRandom
  > = Layer.effect(
    AuthService,
    Effect.gen(function* () {
      const engine = yield* AuthEngine;
      const notices = yield* AccountNotices;
      const repository = yield* AuthRepository;
      const verifier = yield* IdentityVerifier;
      const digest = yield* Digest.Digest;
      const random = yield* SecureRandom.SecureRandom;

      /**
       * Plain SHA-256 is right here: every input is 256 random bits, so there is nothing to guess
       * and a slow hash or salt adds no protection. Lookups go through this hash, so an attacker
       * can't steer a comparison byte by byte; no code here compares a secret directly.
       */
      const hash = (value: string): Effect.Effect<TokenHash> =>
        digest.digestHex(Digest.sha256, encoder.encode(value));

      const opaqueValue = Effect.map(random.randomBytes(opaqueBytes), Base64Url.encode);

      const expiryFrom = (now: EpochMillis, lifetime: Duration.Duration): EpochMillis =>
        now + Duration.toMillis(lifetime);

      // Housekeeping must not cost a user a sign-in that already succeeded.
      const tidy = Effect.flatMap(Clock.currentTimeMillis, repository.deleteExpired).pipe(
        Effect.ignore,
      );

      const issueChallenge = Effect.gen(function* () {
        const nonce = decodeNonce(yield* opaqueValue);
        const expiresAt = expiryFrom(yield* Clock.currentTimeMillis, challengeLifetime);
        yield* repository.saveChallenge(yield* hash(nonce), expiresAt);
        return { nonce, expiresAt };
      });

      /** A fully verified Apple token whose nonce this server issued and nobody has used yet. */
      const verifyApple = Effect.fn("AuthService.verifyApple")(function* (
        identityToken: Redacted.Redacted<string>,
      ): Effect.fn.Return<VerifiedApple, AuthRejected | AuthUnavailable> {
        const identity = yield* verifier.verify(identityToken);
        // Only after the signature checks out, so forged tokens can't burn someone's nonce.
        const fresh = yield* repository.consumeChallenge(
          yield* hash(identity.nonce),
          yield* Clock.currentTimeMillis,
        );
        if (!fresh) return yield* new AuthRejected({ reason: "nonce-not-live" });
        return { identityToken, subject: identity.subject, nonce: identity.nonce };
      });

      const signInAnonymously = Effect.fn("AuthService.signInAnonymously")(function* (
        accountKey: Redacted.Redacted<string>,
      ): Effect.fn.Return<SessionResponse, AuthRejected | AuthUnavailable> {
        const raw = Redacted.value(accountKey);
        if (!isAccountKey(raw)) return yield* new AuthRejected({ reason: "account-key-malformed" });
        const keyHash = yield* hash(raw);

        const known = yield* repository.findAccountKey(keyHash);
        if (Option.isSome(known)) return toResponse(yield* engine.startSession(known.value));

        const opened = yield* engine.signInAnonymous;
        const kept = yield* repository.saveAccountKey(
          keyHash,
          opened.userId,
          yield* Clock.currentTimeMillis,
        );
        if (kept) {
          yield* tidy;
          return toResponse(opened);
        }
        // Another first sign-in with this key won the race: join its account instead.
        yield* engine.endSession(yield* hash(opened.sessionToken));
        const winner = yield* repository.findAccountKey(keyHash);
        if (Option.isNone(winner)) return yield* new AuthRejected({ reason: "account-key-lost" });
        return toResponse(yield* engine.startSession(winner.value));
      });

      const signInWithApple = Effect.fn("AuthService.signInWithApple")(function* (
        identityToken: Redacted.Redacted<string>,
      ): Effect.fn.Return<SessionResponse, AuthRejected | AuthUnavailable> {
        const session = yield* engine.signInWithApple(yield* verifyApple(identityToken));
        yield* tidy;
        return toResponse(session);
      });

      const liveSession = Effect.fnUntraced(function* (sessionToken: Redacted.Redacted<string>) {
        const raw = Redacted.value(sessionToken);
        if (!isSessionToken(raw)) return yield* new AuthRejected({ reason: "session-malformed" });
        const session = yield* engine.findSession(sessionToken);
        if (Option.isNone(session)) return yield* new AuthRejected({ reason: "session-not-live" });
        return { ...session.value, sessionHash: yield* hash(raw) };
      });

      const linkApple = Effect.fn("AuthService.linkApple")(function* (
        sessionToken: Redacted.Redacted<string>,
        identityToken: Redacted.Redacted<string>,
      ): Effect.fn.Return<AccountResponse, AppleIdInUse | AuthRejected | AuthUnavailable> {
        // The caller first, so a stranger can't spend a nonce or probe which Apple IDs are taken.
        const { userId } = yield* liveSession(sessionToken);
        const outcome = yield* engine.linkApple(sessionToken, yield* verifyApple(identityToken));
        if (outcome === "in-use") return yield* new AppleIdInUse();
        return { userId, linked: true };
      });

      const authenticate = Effect.fn("AuthService.authenticate")(function* (
        sessionToken: Redacted.Redacted<string>,
      ): Effect.fn.Return<Principal, AuthRejected | AuthUnavailable> {
        const { userId, deviceId, sessionHash } = yield* liveSession(sessionToken);
        yield* annotateRefs({ user: userId });
        return { userId, deviceId, sessionHash };
      });

      const account = Effect.fn("AuthService.account")(function* (
        sessionToken: Redacted.Redacted<string>,
      ): Effect.fn.Return<AccountResponse, AuthRejected | AuthUnavailable> {
        const { userId, linked } = yield* liveSession(sessionToken);
        const partnerLeft = yield* notices.partnerLeft(userId);
        return Option.match(partnerLeft, {
          onNone: () => ({ userId, linked }),
          onSome: (left) => ({ userId, linked, partnerLeft: left }),
        });
      });

      const registerPushToken = Effect.fn("AuthService.registerPushToken")(function* (
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
        signInAnonymously,
        signInWithApple,
        linkApple,
        authenticate,
        account,
        signOut: (principal) => engine.endSession(principal.sessionHash),
        registerPushToken,
      });
    }),
  );
}
