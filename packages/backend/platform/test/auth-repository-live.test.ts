import { env } from "cloudflare:workers";
import { Effect, Exit, Layer, Scope, Schema } from "effect";
import { beforeEach, describe, expect, it } from "vitest";
import { AuthRepository, type NewSession } from "@billet/backend-auth/auth-repository";
import { describeAuthRepositoryContract } from "@billet/backend-auth/test/auth-repository-contract";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { PushToken } from "@billet/contracts-domain/push-token";
import { AuthRepositoryLive } from "../src/auth-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(AuthRepositoryLive(binding), yield* Scope.make());
      return context.mapUnsafe.get(AuthRepository.key) as AuthRepository["Service"];
    }),
  );

const device = Schema.decodeSync(DeviceId);
const user = Schema.decodeSync(UserId);
const pushToken = Schema.decodeSync(PushToken);

const newSession = (overrides: Partial<NewSession> = {}): NewSession => ({
  appleSubject: "subject-a",
  candidateUserId: user("user-a"),
  deviceId: device("device-a"),
  sessionHash: "hash-a",
  createdAt: 1_000,
  expiresAt: 2_000,
  ...overrides,
});

const countOf = async (table: string) =>
  (await env.DB.prepare(`SELECT count(*) AS total FROM ${table}`).first<{ total: number }>())
    ?.total;

describeAuthRepositoryContract("D1", async () => {
  await resetDirectory();
  return repositoryOn(env.DB);
});

describe("AuthRepositoryLive on D1", () => {
  beforeEach(resetDirectory);

  it("lets only one of many concurrent sign-ins consume a nonce", async () => {
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.saveChallenge("nonce", 2_000));
    const results = await Promise.all(
      Array.from({ length: 8 }, () =>
        Effect.runPromise(repository.consumeChallenge("nonce", 1_000)),
      ),
    );
    expect(results.filter(Boolean)).toHaveLength(1);
  });

  it("gives concurrent first sign-ins of one subject the same user", async () => {
    const repository = await repositoryOn(env.DB);
    const ids = await Promise.all(
      ["a", "b", "c"].map((name) =>
        Effect.runPromise(
          repository.createSession(
            newSession({
              candidateUserId: user(`user-${name}`),
              deviceId: device(`device-${name}`),
              sessionHash: `hash-${name}`,
            }),
          ),
        ),
      ),
    );
    expect(new Set(ids).size).toBe(1);
    expect(await countOf("users")).toBe(1);
    expect(await countOf("devices")).toBe(3);
  });

  it("writes nothing when any step of creating a session fails", async () => {
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.createSession(newSession()));
    const exit = await Effect.runPromiseExit(
      repository.createSession(
        newSession({
          appleSubject: "subject-b",
          candidateUserId: user("user-b"),
          deviceId: device("device-b"),
        }),
      ),
    );
    expect(Exit.isFailure(exit)).toBe(true);
    expect(await countOf("users")).toBe(1);
    expect(await countOf("devices")).toBe(1);
  });

  it("keeps a token on its old device when moving it fails", async () => {
    const repository = await repositoryOn(env.DB);
    const record = {
      kind: "alert",
      environment: "production",
      token: pushToken("aa".repeat(32)),
      updatedAt: 1,
    } as const;
    await Effect.runPromise(repository.createSession(newSession()));
    await Effect.runPromise(repository.savePushToken(device("device-a"), record));
    const exit = await Effect.runPromiseExit(
      repository.savePushToken(device("no-such-device"), record),
    );
    expect(Exit.isFailure(exit)).toBe(true);
    const kept = await Effect.runPromise(repository.listPushTokens(device("device-a")));
    expect(kept).toHaveLength(1);
  });

  it("removes the device and its tokens on sign-out, and keeps the user", async () => {
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.createSession(newSession()));
    await Effect.runPromise(
      repository.savePushToken(device("device-a"), {
        kind: "alert",
        environment: "sandbox",
        token: pushToken("aa".repeat(32)),
        updatedAt: 1,
      }),
    );
    await Effect.runPromise(repository.revokeSession("hash-a"));
    expect(await countOf("sessions")).toBe(0);
    expect(await countOf("devices")).toBe(0);
    expect(await countOf("push_tokens")).toBe(0);
    expect(await countOf("users")).toBe(1);
  });

  it("removes an expired session's device, and leaves other devices alone", async () => {
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.createSession(newSession()));
    await Effect.runPromise(
      repository.createSession(
        newSession({ deviceId: device("device-b"), sessionHash: "hash-b", expiresAt: 4_000 }),
      ),
    );
    await Effect.runPromise(repository.deleteExpired(3_000));
    const remaining = await env.DB.prepare("SELECT id FROM devices").all();
    expect(remaining.results).toEqual([{ id: "device-b" }]);
  });

  it.each([
    [
      "a single statement",
      (repository: AuthRepository["Service"]) => repository.findSession("h", 1),
    ],
    ["a batch", (repository: AuthRepository["Service"]) => repository.deleteExpired(1)],
  ])("reports AuthUnavailable when %s fails", async (_, run) => {
    const broken = {
      prepare: () => {
        throw new Error("D1 is down, token hash h");
      },
    } as unknown as D1Database;
    const exit = await Effect.runPromiseExit(run(await repositoryOn(broken)));
    expect(Exit.isFailure(exit)).toBe(true);
    const text = JSON.stringify(exit);
    expect(text).toContain("directory-unavailable");
    expect(text).not.toContain("token hash");
  });
});
