import { kyselyAdapter } from "@better-auth/kysely-adapter";
import type { BetterAuthOptions } from "better-auth";
import { betterAuth } from "better-auth";
import { anonymous } from "better-auth/plugins/anonymous";
import { bearer } from "better-auth/plugins/bearer";
import { Duration, Effect, Layer, Option, Redacted, Schema } from "effect";
import { Kysely } from "kysely";
import { AuthRejected, AuthUnavailable } from "@billet/backend-auth/auth-error";
import {
  AuthEngine,
  type IssuedSession,
  type LinkOutcome,
  type VerifiedApple,
} from "@billet/backend-auth/auth-engine";
import { appleAudience } from "@billet/backend-auth/apple-identity-verifier";
import { sessionLifetime, sessionRenewalInterval } from "@billet/backend-auth/auth-service";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { SessionToken } from "@billet/contracts-http-api/auth";
import { D1Dialect } from "./d1-kysely-dialect.ts";
import { hashSessionTokens, sha256Hex } from "./hashed-session-tokens.ts";
import { spanMethods } from "@billet/backend-observability/span-methods";
import { type Now, systemNow } from "./wall-clock.ts";

const IssuedRow = Schema.Struct({
  token: SessionToken,
  userId: UserId,
  deviceId: DeviceId,
  expiresAt: Schema.Date,
});
const decodeIssued = Schema.decodeUnknownSync(IssuedRow);

/** A failure inside Better Auth can quote a token or a bound value, so none of it survives. */
const unavailable = (cause?: unknown) =>
  new AuthUnavailable({ reason: "auth-engine-unavailable", cause });

const attempt = <A>(run: () => Promise<A>) => Effect.tryPromise({ try: run, catch: unavailable });

const bearerHeaders = (token: string) => new Headers({ authorization: `Bearer ${token}` });

const errorCode = (error: unknown): string | undefined => {
  const body = (error as { body?: { code?: unknown } } | null)?.body;
  return typeof body?.code === "string" ? body.code : undefined;
};

/** Per request (holds D1). Never mounted; the secret signs only a same-request cookie: random. */
const makeBetterAuth = (db: D1Database, verified: ReadonlyMap<string, string>, now: Now) => {
  const secret = [...crypto.getRandomValues(new Uint8Array(32))]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  const adapter = kyselyAdapter(new Kysely({ dialect: new D1Dialect(db) }), {
    type: "sqlite",
    transaction: false,
  });
  const withoutTokens = { accessToken: null, refreshToken: null, idToken: null };
  const timestamps = { createdAt: "created_at", updatedAt: "updated_at" };

  return betterAuth({
    appName: "billet",
    baseURL: "https://api.billet.invalid",
    secret,
    database: (options: BetterAuthOptions) => hashSessionTokens(adapter(options)),
    telemetry: { enabled: false },
    logger: { disabled: true },
    rateLimit: { enabled: false },
    advanced: { database: { generateId: () => crypto.randomUUID() } },
    user: {
      modelName: "auth_user",
      fields: { emailVerified: "email_verified", ...timestamps },
    },
    session: {
      modelName: "auth_session",
      fields: {
        token: "token",
        userId: "user_id",
        expiresAt: "expires_at",
        ipAddress: "ip_address",
        userAgent: "user_agent",
        ...timestamps,
      },
      expiresIn: Duration.toSeconds(sessionLifetime),
      updateAge: Duration.toSeconds(sessionRenewalInterval),
      additionalFields: {
        deviceId: { type: "string", fieldName: "device_id", required: false, input: false },
      },
    },
    account: {
      modelName: "auth_account",
      fields: {
        accountId: "account_id",
        providerId: "provider_id",
        userId: "user_id",
        accessToken: "access_token",
        refreshToken: "refresh_token",
        idToken: "id_token",
        accessTokenExpiresAt: "access_token_expires_at",
        refreshTokenExpiresAt: "refresh_token_expires_at",
        ...timestamps,
      },
      accountLinking: {
        enabled: true,
        trustedProviders: ["apple"],
        allowDifferentEmails: true,
        disableImplicitLinking: true,
      },
    },
    verification: {
      modelName: "auth_verification",
      fields: { expiresAt: "expires_at", ...timestamps },
    },
    socialProviders: {
      apple: {
        clientId: appleAudience,
        clientSecret: "",
        appBundleIdentifier: appleAudience,
        verifyIdToken: (token) => Promise.resolve(verified.has(token)),
        getUserInfo: (tokens) => {
          const subject = tokens.idToken === undefined ? undefined : verified.get(tokens.idToken);
          if (subject === undefined) return Promise.resolve(null);
          const email = `${crypto.randomUUID()}@apple.billet.invalid`;
          // Only `sub` is read; the rest fills the shape of Apple's profile with nothing personal.
          return Promise.resolve({
            user: { name: "", email, emailVerified: false },
            data: {
              sub: subject,
              email_verified: true,
              is_private_email: true,
              real_user_status: 0,
              name: "",
              picture: "",
            },
          });
        },
      },
    },
    plugins: [
      anonymous({
        emailDomainName: "anonymous.billet.invalid",
        generateName: () => "",
        disableDeleteAnonymousUser: true,
        schema: { user: { fields: { isAnonymous: "is_anonymous" } } },
      }),
      bearer(),
    ],
    databaseHooks: {
      user: {
        create: {
          // Idempotent, so a retried sign-up can't fail here.
          after: async (user) => {
            await db
              .prepare("INSERT INTO users (id, created_at) VALUES (?, ?) ON CONFLICT DO NOTHING")
              .bind(user.id, user.createdAt.getTime())
              .run();
          },
        },
      },
      session: {
        create: {
          // Made first so the session's foreign key holds.
          before: async (session) => {
            const deviceId = crypto.randomUUID();
            await db
              .prepare("INSERT INTO devices (id, user_id, created_at) VALUES (?, ?, ?)")
              .bind(deviceId, session.userId, now())
              .run();
            return { data: { ...session, deviceId } };
          },
        },
      },
      account: {
        create: {
          before: (account) => Promise.resolve({ data: { ...account, ...withoutTokens } }),
          // An Apple ID makes the account recoverable, which is all `is_anonymous` means here.
          after: async (account) => {
            if (account.providerId !== "apple") return;
            await db
              .prepare("UPDATE auth_user SET is_anonymous = 0 WHERE id = ?")
              .bind(account.userId)
              .run();
          },
        },
        update: {
          before: (account) => Promise.resolve({ data: { ...account, ...withoutTokens } }),
        },
      },
    },
  });
};

/** Build it once per request, as the other directory layers are. */
export const BetterAuthEngineLive = (
  db: D1Database,
  now: Now = systemNow,
): Layer.Layer<AuthEngine> =>
  Layer.sync(AuthEngine, () => {
    const verified = new Map<string, string>();
    const auth = makeBetterAuth(db, verified, now);

    const issued = Effect.fnUntraced(function* (token: string) {
      const context = yield* attempt(() => auth.$context);
      const found = yield* attempt(() => context.internalAdapter.findSession(token));
      if (found === null) return yield* unavailable();
      const { session } = found;
      return yield* Effect.try({
        try: (): IssuedSession => {
          const row = decodeIssued({ ...session, token });
          return { ...row, sessionToken: row.token, expiresAt: row.expiresAt.getTime() };
        },
        catch: unavailable,
      });
    });

    const trusting = <A>(apple: VerifiedApple, run: (token: string) => Promise<A>) => {
      const token = Redacted.value(apple.identityToken);
      return attempt(() => {
        verified.set(token, apple.subject);
        return run(token);
      }).pipe(Effect.ensuring(Effect.sync(() => verified.delete(token))));
    };

    const appleOwner = (subject: string) =>
      attempt(() =>
        db
          .prepare(
            "SELECT user_id FROM auth_account WHERE provider_id = 'apple' AND account_id = ?",
          )
          .bind(subject)
          .first<{ user_id: string }>(),
      ).pipe(Effect.map((row) => row?.user_id));

    const callerOf = (sessionToken: Redacted.Redacted<string>) =>
      attempt(async () => {
        const hash = await sha256Hex(Redacted.value(sessionToken));
        const row = await db
          .prepare("SELECT user_id FROM auth_session WHERE token = ?")
          .bind(hash)
          .first<{ user_id: string }>();
        return row?.user_id;
      });

    const live = Schema.decodeUnknownSync(
      Schema.Struct({
        user: Schema.Struct({
          id: UserId,
          isAnonymous: Schema.optional(Schema.NullOr(Schema.Boolean)),
        }),
        session: Schema.Struct({ deviceId: DeviceId }),
      }),
    );

    return AuthEngine.of(
      spanMethods("AuthEngine", {
        signInAnonymous: attempt(() => auth.api.signInAnonymous()).pipe(
          Effect.flatMap((result) => (result === null ? unavailable() : issued(result.token))),
        ),

        startSession: (userId) =>
          Effect.gen(function* () {
            const context = yield* attempt(() => auth.$context);
            const user = yield* attempt(() => context.internalAdapter.findUserById(userId));
            if (user === null) return yield* new AuthRejected({ reason: "user-gone" });
            const session = yield* attempt(() => context.internalAdapter.createSession(userId));
            return yield* issued(session.token);
          }),

        // Two concurrent first sign-ins with one Apple ID: the second link fails on the unique
        // index, and trying again finds the first link and signs in to that user.
        signInWithApple: (apple) =>
          trusting(apple, (token) =>
            auth.api.signInSocial({
              body: { provider: "apple", idToken: { token, nonce: apple.nonce } },
            }),
          ).pipe(
            Effect.retry({ times: 1 }),
            Effect.flatMap((result) =>
              "token" in result && typeof result.token === "string"
                ? issued(result.token)
                : unavailable(),
            ),
          ),

        linkApple: (sessionToken, apple) =>
          trusting(apple, (token) =>
            auth.api
              .linkSocialAccount({
                headers: bearerHeaders(Redacted.value(sessionToken)),
                body: { provider: "apple", idToken: { token, nonce: apple.nonce } },
              })
              .then(
                (): LinkOutcome | "lost" => "linked",
                (error: unknown): LinkOutcome | "lost" => {
                  const code = errorCode(error);
                  if (code === "SOCIAL_ACCOUNT_ALREADY_LINKED") return "in-use";
                  // Another link of this Apple ID won a race for the unique index.
                  if (code === "LINKING_FAILED") return "lost";
                  throw error;
                },
              ),
          ).pipe(
            Effect.flatMap((outcome) =>
              outcome !== "lost"
                ? Effect.succeed(outcome)
                : Effect.gen(function* () {
                    // Linked after all if the winner was this same user on another of its phones.
                    const owner = yield* appleOwner(apple.subject);
                    const caller = yield* callerOf(sessionToken);
                    return owner !== undefined && owner === caller ? "linked" : "in-use";
                  }),
            ),
          ),

        findSession: (sessionToken) =>
          attempt(() =>
            auth.api.getSession({
              headers: bearerHeaders(Redacted.value(sessionToken)),
              query: { disableCookieCache: true },
            }),
          ).pipe(
            Effect.flatMap((found) =>
              found === null
                ? Effect.succeedNone
                : Effect.try({ try: () => live(found), catch: unavailable }).pipe(
                    Effect.map(({ user, session }) =>
                      Option.some({
                        userId: user.id,
                        deviceId: session.deviceId,
                        linked: user.isAnonymous !== true,
                      }),
                    ),
                  ),
            ),
          ),

        endSession: (sessionHash) =>
          attempt(() =>
            db
              .prepare(
                "DELETE FROM devices WHERE id IN (SELECT device_id FROM auth_session WHERE token = ?)",
              )
              .bind(sessionHash)
              .run(),
          ).pipe(Effect.asVoid),
      }),
    );
  });
