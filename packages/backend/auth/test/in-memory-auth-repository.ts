import { Effect, Option } from "effect";
import type { DeviceId, EpochMillis } from "@billet/contracts-domain/ids";
import type {
  AuthRepository,
  NewSession,
  PushTokenRecord,
  SessionRecord,
  TokenHash,
} from "../src/auth-repository.ts";

export interface InMemoryAuthRepository {
  readonly repository: AuthRepository["Service"];
  /** Everything stored, as text, for assertions about what is and isn't kept. */
  readonly dump: Effect.Effect<string>;
}

/** The test double for `AuthRepository`. Single-threaded, so each method is trivially atomic. */
export const makeInMemoryAuthRepository = (): InMemoryAuthRepository => {
  const challenges = new Map<TokenHash, EpochMillis>();
  const users = new Map<string, NewSession["candidateUserId"]>();
  const devices = new Map<DeviceId, NewSession["candidateUserId"]>();
  const sessions = new Map<TokenHash, SessionRecord>();
  const pushTokens = new Map<DeviceId, ReadonlyArray<PushTokenRecord>>();

  const repository: AuthRepository["Service"] = {
    saveChallenge: (nonceHash, expiresAt) =>
      Effect.sync(() => {
        challenges.set(nonceHash, expiresAt);
      }),
    consumeChallenge: (nonceHash, now) =>
      Effect.sync(() => {
        const expiresAt = challenges.get(nonceHash);
        challenges.delete(nonceHash);
        return expiresAt !== undefined && expiresAt > now;
      }),
    createSession: (session) =>
      Effect.sync(() => {
        const userId = users.get(session.appleSubject) ?? session.candidateUserId;
        users.set(session.appleSubject, userId);
        devices.set(session.deviceId, userId);
        sessions.set(session.sessionHash, {
          userId,
          deviceId: session.deviceId,
          expiresAt: session.expiresAt,
        });
        return userId;
      }),
    findSession: (sessionHash, now) =>
      Effect.sync(() =>
        Option.fromNullishOr(sessions.get(sessionHash)).pipe(
          Option.filter((session) => session.expiresAt > now),
        ),
      ),
    extendSession: (sessionHash, expiresAt) =>
      Effect.sync(() => {
        const session = sessions.get(sessionHash);
        if (session !== undefined) sessions.set(sessionHash, { ...session, expiresAt });
      }),
    revokeSession: (sessionHash) =>
      Effect.sync(() => {
        const session = sessions.get(sessionHash);
        if (session === undefined) return;
        sessions.delete(sessionHash);
        devices.delete(session.deviceId);
        pushTokens.delete(session.deviceId);
      }),
    savePushToken: (deviceId, record) =>
      Effect.sync(() => {
        for (const [holder, records] of pushTokens) {
          pushTokens.set(
            holder,
            records.filter((held) => held.token !== record.token || held.kind !== record.kind),
          );
        }
        const others = (pushTokens.get(deviceId) ?? []).filter((held) => held.kind !== record.kind);
        pushTokens.set(deviceId, [...others, record]);
      }),
    listPushTokens: (deviceId) => Effect.sync(() => pushTokens.get(deviceId) ?? []),
    deleteExpired: (now) =>
      Effect.sync(() => {
        for (const [hash, expiresAt] of challenges) {
          if (expiresAt <= now) challenges.delete(hash);
        }
        for (const [hash, session] of sessions) {
          if (session.expiresAt > now) continue;
          sessions.delete(hash);
          devices.delete(session.deviceId);
          pushTokens.delete(session.deviceId);
        }
      }),
  };

  const dump = Effect.sync(() =>
    JSON.stringify({
      challenges: [...challenges],
      users: [...users],
      devices: [...devices],
      sessions: [...sessions],
      pushTokens: [...pushTokens],
    }),
  );

  return { repository, dump };
};
