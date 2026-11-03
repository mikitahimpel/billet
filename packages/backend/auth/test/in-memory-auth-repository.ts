import { Effect, Option } from "effect";
import type { DeviceId, EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type { AuthRepository, PushTokenRecord, TokenHash } from "../src/auth-repository.ts";

export interface InMemoryAuthRepository {
  readonly repository: AuthRepository["Service"];
  /** Everything stored, as text, for assertions about what is and isn't kept. */
  readonly dump: Effect.Effect<string>;
}

/** The test double for `AuthRepository`. Single-threaded, so each method is trivially atomic. */
export const makeInMemoryAuthRepository = (): InMemoryAuthRepository => {
  const challenges = new Map<TokenHash, EpochMillis>();
  const accountKeys = new Map<TokenHash, UserId>();
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
    findAccountKey: (keyHash) => Effect.sync(() => Option.fromNullishOr(accountKeys.get(keyHash))),
    saveAccountKey: (keyHash, userId) =>
      Effect.sync(() => {
        if (accountKeys.has(keyHash)) return false;
        accountKeys.set(keyHash, userId);
        return true;
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
      }),
  };

  const dump = Effect.sync(() =>
    JSON.stringify({
      challenges: [...challenges],
      accountKeys: [...accountKeys],
      pushTokens: [...pushTokens],
    }),
  );

  return { repository, dump };
};
