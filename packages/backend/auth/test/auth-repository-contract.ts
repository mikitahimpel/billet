import { Effect, Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { PushToken } from "@billet/contracts-domain/push-token";
import type { AuthRepository } from "../src/auth-repository.ts";

const user = Schema.decodeSync(UserId);
const device = Schema.decodeSync(DeviceId);
const pushToken = Schema.decodeSync(PushToken);

const alert = pushToken("aa".repeat(32));
const widget = pushToken("bb".repeat(32));

export interface AuthRepositoryFixture {
  readonly repository: AuthRepository["Service"];
  /** Creates the user if needed, then a device of theirs, as a sign-in would. */
  readonly seedDevice: (deviceId: DeviceId, userId: UserId) => Promise<void>;
}

/**
 * The behaviour every `AuthRepository` must have. Run it against each implementation, so the
 * in-memory fake can't drift from the real one. `make` must return an empty repository.
 */
export const describeAuthRepositoryContract = (
  name: string,
  make: () => Promise<AuthRepositoryFixture>,
): void => {
  describe(`AuthRepository contract: ${name}`, () => {
    it("consumes a challenge exactly once", async () => {
      const { repository } = await make();
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
      const { repository } = await make();
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

    it("replaces a device's token of the same kind and keeps other kinds", async () => {
      const { repository, seedDevice } = await make();
      const deviceId = device("device-a");
      await seedDevice(deviceId, user("user-a"));
      const stored = await Effect.runPromise(
        Effect.gen(function* () {
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
      const { repository, seedDevice } = await make();
      await seedDevice(device("device-a"), user("user-a"));
      await seedDevice(device("device-b"), user("user-a"));
      const [before, after] = await Effect.runPromise(
        Effect.gen(function* () {
          const record = {
            kind: "alert",
            environment: "production",
            token: alert,
            updatedAt: 1,
          } as const;
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

    it("deletes expired challenges and keeps live ones", async () => {
      const { repository } = await make();
      const [expired, live] = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.saveChallenge("old", 1_000);
          yield* repository.saveChallenge("new", 3_000);
          yield* repository.deleteExpired(2_500);
          return [
            // Read back at an earlier time, so only a real delete can make these disappear.
            yield* repository.consumeChallenge("old", 500),
            yield* repository.consumeChallenge("new", 500),
          ] as const;
        }),
      );
      expect(expired).toBe(false);
      expect(live).toBe(true);
    });

    it("keeps each account key with the user it opened, first come first served", async () => {
      const { repository, seedDevice } = await make();
      await seedDevice(device("device-a"), user("user-a"));
      await seedDevice(device("device-b"), user("user-b"));
      const result = await Effect.runPromise(
        Effect.gen(function* () {
          const unknown = yield* repository.findAccountKey("key-a");
          const first = yield* repository.saveAccountKey("key-a", user("user-a"), 1_000);
          const second = yield* repository.saveAccountKey("key-a", user("user-b"), 1_001);
          return [unknown, first, second, yield* repository.findAccountKey("key-a")] as const;
        }),
      );
      expect(result).toEqual([Option.none(), true, false, Option.some("user-a")]);
    });
  });
};
