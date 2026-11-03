import { Clock, Duration, Effect, Option, Redacted, Schema } from "effect";
import { DeviceId, type EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { SessionToken } from "@billet/contracts-http-api/auth";
import { AuthRejected } from "../src/auth-error.ts";
import type { AuthEngine, IssuedSession } from "../src/auth-engine.ts";
import type { TokenHash } from "../src/auth-repository.ts";
import { sessionLifetime } from "../src/auth-service.ts";

interface StoredSession {
  readonly userId: UserId;
  readonly deviceId: DeviceId;
  expiresAt: EpochMillis;
}

export interface InMemoryAuthEngine {
  readonly engine: AuthEngine["Service"];
  /** Everything stored, as text, for assertions about what is and isn't kept. */
  readonly dump: Effect.Effect<string>;
  readonly userCount: Effect.Effect<number>;
}

const sha256 = (value: string): Effect.Effect<TokenHash> =>
  Effect.promise(async () =>
    [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join(""),
  );

/** The test double for `AuthEngine`: sliding sessions keyed by token hash, as the real one keeps. */
export const makeInMemoryAuthEngine = (): InMemoryAuthEngine => {
  const users = new Map<UserId, { appleSubject: string | undefined }>();
  const sessions = new Map<TokenHash, StoredSession>();
  let counter = 0;

  const issue = Effect.fnUntraced(function* (userId: UserId) {
    counter += 1;
    const sessionToken = Schema.decodeSync(SessionToken)(crypto.randomUUID().replaceAll("-", ""));
    const deviceId = Schema.decodeSync(DeviceId)(`device-${counter}`);
    const expiresAt = (yield* Clock.currentTimeMillis) + Duration.toMillis(sessionLifetime);
    sessions.set(yield* sha256(sessionToken), { userId, deviceId, expiresAt });
    const issued: IssuedSession = { sessionToken, userId, deviceId, expiresAt };
    return issued;
  });

  const newUser = (appleSubject: string | undefined) => {
    counter += 1;
    const userId = Schema.decodeSync(UserId)(`user-${counter}`);
    users.set(userId, { appleSubject });
    return userId;
  };

  const live = Effect.fnUntraced(function* (token: Redacted.Redacted<string>) {
    const session = sessions.get(yield* sha256(Redacted.value(token)));
    const now = yield* Clock.currentTimeMillis;
    if (session === undefined || session.expiresAt <= now) return Option.none<StoredSession>();
    session.expiresAt = now + Duration.toMillis(sessionLifetime);
    return Option.some(session);
  });

  const userOfSubject = (subject: string) =>
    [...users].find(([, user]) => user.appleSubject === subject)?.[0];

  const engine: AuthEngine["Service"] = {
    signInAnonymous: Effect.suspend(() => issue(newUser(undefined))),
    startSession: (userId) =>
      users.has(userId) ? issue(userId) : Effect.fail(new AuthRejected({ reason: "user-gone" })),
    signInWithApple: (apple) =>
      Effect.suspend(() => issue(userOfSubject(apple.subject) ?? newUser(apple.subject))),
    linkApple: (token, apple) =>
      Effect.gen(function* () {
        const session = yield* live(token);
        if (Option.isNone(session)) return yield* new AuthRejected({ reason: "session-not-live" });
        const owner = userOfSubject(apple.subject);
        if (owner !== undefined) return owner === session.value.userId ? "linked" : "in-use";
        users.set(session.value.userId, { appleSubject: apple.subject });
        return "linked";
      }),
    findSession: (token) =>
      Effect.map(
        live(token),
        Option.map(({ userId, deviceId }) => ({
          userId,
          deviceId,
          linked: users.get(userId)?.appleSubject !== undefined,
        })),
      ),
    endSession: (sessionHash) =>
      Effect.sync(() => {
        sessions.delete(sessionHash);
      }),
  };

  return {
    engine,
    dump: Effect.sync(() => JSON.stringify({ users: [...users], sessions: [...sessions] })),
    userCount: Effect.sync(() => users.size),
  };
};
