import { Effect, Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { PushToken } from "@billet/contracts-domain/push-token";
import type { AuthRepository, NewSession } from "../src/auth-repository.ts";

const user = Schema.decodeSync(UserId);
const device = Schema.decodeSync(DeviceId);
const pushToken = Schema.decodeSync(PushToken);

const session = (overrides: Partial<NewSession> = {}): NewSession => ({
  appleSubject: "subject-a",
  candidateUserId: user("user-a"),
  deviceId: device("device-a"),
  sessionHash: "hash-a",
  createdAt: 1_000,
  expiresAt: 2_000,
  ...overrides,
});

const alert = pushToken("aa".repeat(32));
const widget = pushToken("bb".repeat(32));

/**
 * The behaviour every `AuthRepository` must have. Run it against each implementation, so the
 * in-memory fake can't drift from the real one. `make` must return an empty repository.
 */
export const describeAuthRepositoryContract = (
  name: string,
  make: () => Promise<AuthRepository["Service"]>,
): void => {
  describe(`AuthRepository contract: ${name}`, () => {
    it("consumes a challenge exactly once", async () => {
      const repository = await make();
      const result = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveChallenge("nonce", 2_000);
          return [
            yield* repository.consumeChallenge("nonce", 1_000),
            yield* repository.consumeChallenge("nonce", 1_000),
          ];
        }),
      );
      expect(result).toEqual([true, false]);
    });

    it("refuses an unknown challenge and one at or past its expiry", async () => {
      const repository = await make();
      const result = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveChallenge("nonce", 2_000);
          return [
            yield* repository.consumeChallenge("other", 1_000),
            yield* repository.consumeChallenge("nonce", 2_000),
          ];
        }),
      );
      expect(result).toEqual([false, false]);
    });

    it("reuses the user for a subject, and creates one for a new subject", async () => {
      const repository = await make();
      const result = await Effect.runPromise(
        Effect.gen(function* () {
          const first = yield* repository.createSession(session());
          const again = yield* repository.createSession(
            session({
              candidateUserId: user("user-unused"),
              deviceId: device("device-b"),
              sessionHash: "hash-b",
            }),
          );
          const other = yield* repository.createSession(
            session({
              appleSubject: "subject-c",
              candidateUserId: user("user-c"),
              deviceId: device("device-c"),
              sessionHash: "hash-c",
            }),
          );
          return [first, again, other];
        }),
      );
      expect(result).toEqual(["user-a", "user-a", "user-c"]);
    });

    it("finds a live session, and neither an unknown nor an expired one", async () => {
      const repository = await make();
      const result = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.createSession(session());
          return [
            yield* repository.findSession("hash-a", 1_999),
            yield* repository.findSession("unknown", 1_999),
            yield* repository.findSession("hash-a", 2_000),
          ];
        }),
      );
      expect(result[0]).toEqual(
        Option.some({ userId: "user-a", deviceId: "device-a", expiresAt: 2_000 }),
      );
      expect(result[1]).toEqual(Option.none());
      expect(result[2]).toEqual(Option.none());
    });

    it("extends a session", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.createSession(session());
          yield* repository.extendSession("hash-a", 3_000);
          return yield* repository.findSession("hash-a", 2_500);
        }),
      );
      expect(Option.isSome(found)).toBe(true);
    });

    it("replaces a device's token of the same kind and keeps other kinds", async () => {
      const repository = await make();
      const deviceId = device("device-a");
      const stored = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.createSession(session());
          const common = { environment: "production", updatedAt: 1 } as const;
          yield* repository.savePushToken(deviceId, { ...common, kind: "alert", token: alert });
          yield* repository.savePushToken(deviceId, { ...common, kind: "widget", token: widget });
          yield* repository.savePushToken(deviceId, {
            ...common,
            kind: "alert",
            token: pushToken("cc".repeat(32)),
            updatedAt: 2,
          });
          return yield* repository.listPushTokens(deviceId);
        }),
      );
      expect(
        stored.map(({ kind, token, updatedAt }) => [kind, token, updatedAt]).toSorted(),
      ).toEqual([
        ["alert", "cc".repeat(32), 2],
        ["widget", widget, 1],
      ]);
    });

    it("moves a token to the device that registered it last", async () => {
      const repository = await make();
      const [before, after] = await Effect.runPromise(
        Effect.gen(function* () {
          const record = {
            kind: "alert",
            environment: "production",
            token: alert,
            updatedAt: 1,
          } as const;
          yield* repository.createSession(session());
          yield* repository.createSession(
            session({ deviceId: device("device-b"), sessionHash: "hash-b" }),
          );
          yield* repository.savePushToken(device("device-a"), record);
          yield* repository.savePushToken(device("device-b"), record);
          return [
            yield* repository.listPushTokens(device("device-a")),
            yield* repository.listPushTokens(device("device-b")),
          ];
        }),
      );
      expect(before).toEqual([]);
      expect(after.map(({ token }) => token)).toEqual([alert]);
    });

    it("revokes a session together with its device's push tokens", async () => {
      const repository = await make();
      const deviceId = device("device-a");
      const [found, tokens] = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.createSession(session());
          yield* repository.savePushToken(deviceId, {
            kind: "alert",
            environment: "sandbox",
            token: alert,
            updatedAt: 1,
          });
          yield* repository.revokeSession("hash-a");
          return [
            yield* repository.findSession("hash-a", 1_000),
            yield* repository.listPushTokens(deviceId),
          ] as const;
        }),
      );
      expect(Option.isNone(found)).toBe(true);
      expect(tokens).toEqual([]);
    });

    it("deletes what expired and keeps what is live", async () => {
      const repository = await make();
      const [expiredChallenge, liveChallenge, liveSession, expiredTokens, liveTokens] =
        await Effect.runPromise(
          Effect.gen(function* () {
            yield* repository.saveChallenge("old", 1_000);
            yield* repository.saveChallenge("new", 3_000);
            yield* repository.createSession(session());
            yield* repository.createSession(
              session({
                deviceId: device("device-b"),
                sessionHash: "hash-b",
                expiresAt: 4_000,
              }),
            );
            const common = { kind: "alert", environment: "sandbox", updatedAt: 1 } as const;
            yield* repository.savePushToken(device("device-a"), { ...common, token: alert });
            yield* repository.savePushToken(device("device-b"), { ...common, token: widget });
            yield* repository.deleteExpired(2_500);
            return [
              // Read back at an earlier time, so only a real delete can make these disappear.
              yield* repository.consumeChallenge("old", 500),
              yield* repository.consumeChallenge("new", 500),
              yield* repository.findSession("hash-b", 500),
              yield* repository.listPushTokens(device("device-a")),
              yield* repository.listPushTokens(device("device-b")),
            ] as const;
          }),
        );
      expect(expiredChallenge).toBe(false);
      expect(liveChallenge).toBe(true);
      expect(Option.isSome(liveSession)).toBe(true);
      expect(expiredTokens).toEqual([]);
      expect(liveTokens.map(({ token }) => token)).toEqual([widget]);
    });
  });
};
