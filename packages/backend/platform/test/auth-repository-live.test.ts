import { env } from "cloudflare:workers";
import { Effect, Exit, Layer, Scope, Schema } from "effect";
import { beforeEach, describe, expect, it } from "vitest";
import { AuthRepository } from "@billet/backend-auth/auth-repository";
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

/**
 * When the tests sweep: 01:00 UTC on 2026-03-29, the hour Europe moves its clocks forward. The
 * repository takes the time it is given, so nothing here reads the real clock.
 */
const now = Date.UTC(2026, 2, 29, 1);

/** A user and a device of theirs, as a sign-in leaves them. */
const seedDevice = async (deviceId: string, userId: string, createdAt = now) => {
  await env.DB.batch([
    env.DB.prepare("INSERT INTO users (id, created_at) VALUES (?, 1) ON CONFLICT DO NOTHING").bind(
      userId,
    ),
    env.DB.prepare("INSERT INTO devices (id, user_id, created_at) VALUES (?, ?, ?)").bind(
      deviceId,
      userId,
      createdAt,
    ),
  ]);
};

/** A Better Auth session on a seeded device, expiring at `expiresAt`. */
const seedSession = async (deviceId: string, userId: string, expiresAt: number) => {
  const iso = new Date(expiresAt).toISOString();
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO auth_user (id, name, email, email_verified, created_at, updated_at) VALUES (?, '', ?, 0, ?, ?) ON CONFLICT DO NOTHING",
    ).bind(userId, `${userId}@test.invalid`, iso, iso),
    env.DB.prepare(
      "INSERT INTO auth_session (id, token, user_id, device_id, expires_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    ).bind(`session-${deviceId}`, `hash-${deviceId}`, userId, deviceId, iso, iso, iso),
  ]);
};

const countOf = async (table: string) =>
  (await env.DB.prepare(`SELECT count(*) AS total FROM ${table}`).first<{ total: number }>())
    ?.total;

describeAuthRepositoryContract("D1", async () => {
  await resetDirectory();
  return { repository: await repositoryOn(env.DB), seedDevice };
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

  it("keeps one user for a key that many first sign-ins save at once", async () => {
    const repository = await repositoryOn(env.DB);
    const names = ["a", "b", "c", "d"];
    for (const name of names) await seedDevice(`device-${name}`, `user-${name}`);
    const saved = await Promise.all(
      names.map((name) =>
        Effect.runPromise(repository.saveAccountKey("key", user(`user-${name}`), 1)),
      ),
    );
    expect(saved.filter(Boolean)).toHaveLength(1);
    expect(await countOf("account_keys")).toBe(1);
  });

  it("forgets a user's account keys with the user", async () => {
    const repository = await repositoryOn(env.DB);
    await seedDevice("device-a", "user-a");
    await Effect.runPromise(repository.saveAccountKey("key", user("user-a"), 1));
    await env.DB.batch([
      env.DB.prepare("DELETE FROM devices"),
      env.DB.prepare("DELETE FROM users"),
    ]);
    expect(await countOf("account_keys")).toBe(0);
  });

  it("keeps a token on its old device when moving it fails", async () => {
    const repository = await repositoryOn(env.DB);
    const record = {
      kind: "alert",
      environment: "production",
      token: pushToken("aa".repeat(32)),
      updatedAt: 1,
    } as const;
    await seedDevice("device-a", "user-a");
    await Effect.runPromise(repository.savePushToken(device("device-a"), record));
    const exit = await Effect.runPromiseExit(
      repository.savePushToken(device("no-such-device"), record),
    );
    expect(Exit.isFailure(exit)).toBe(true);
    const kept = await Effect.runPromise(repository.listPushTokens(device("device-a")));
    expect(kept).toHaveLength(1);
  });

  it("removes users no one can reach, and keeps every user something still points at", async () => {
    const repository = await repositoryOn(env.DB);
    const old = now - 2 * 60 * 60 * 1000;
    const iso = new Date(old).toISOString();
    const userAt = (id: string, createdAt: number) => [
      env.DB.prepare("INSERT INTO users (id, created_at) VALUES (?, ?)").bind(id, createdAt),
      env.DB.prepare(
        "INSERT INTO auth_user (id, name, email, email_verified, created_at, updated_at) VALUES (?, '', ?, 0, ?, ?)",
      ).bind(id, `${id}@test.invalid`, iso, iso),
    ];
    await env.DB.batch([
      // Lost a race to link an Apple ID: nothing points at it.
      ...userAt("user-lost", old),
      // Mid sign-in: too new to judge.
      ...userAt("user-new", now),
      ...userAt("user-linked", old),
      env.DB.prepare(
        "INSERT INTO auth_account (id, account_id, provider_id, user_id, created_at, updated_at) VALUES ('a', 'subject', 'apple', 'user-linked', ?, ?)",
      ).bind(iso, iso),
      ...userAt("user-keyed", old),
      env.DB.prepare(
        "INSERT INTO account_keys (key_hash, user_id, created_at) VALUES ('hash', 'user-keyed', 1)",
      ),
    ]);
    await Effect.runPromise(repository.deleteExpired(now));
    const left = await env.DB.prepare("SELECT id FROM users ORDER BY id").all<{ id: string }>();
    expect(left.results.map(({ id }) => id)).toEqual(["user-keyed", "user-linked", "user-new"]);
    const authLeft = await env.DB.prepare("SELECT id FROM auth_user ORDER BY id").all<{
      id: string;
    }>();
    expect(authLeft.results.map(({ id }) => id)).toEqual(["user-keyed", "user-linked", "user-new"]);
  });

  it("removes expired sessions with their devices and tokens, and old devices with none", async () => {
    const repository = await repositoryOn(env.DB);
    await seedDevice("device-expired", "user-a");
    await seedSession("device-expired", "user-a", now - 1);
    await seedDevice("device-live", "user-a");
    await seedSession("device-live", "user-a", now + 60_000);
    await seedDevice("device-orphan", "user-a", now - 2 * 60 * 60 * 1000);
    await seedDevice("device-signing-in", "user-a");
    await Effect.runPromise(
      repository.savePushToken(device("device-expired"), {
        kind: "alert",
        environment: "sandbox",
        token: pushToken("aa".repeat(32)),
        updatedAt: 1,
      }),
    );
    await Effect.runPromise(repository.deleteExpired(now));
    const remaining = await env.DB.prepare("SELECT id FROM devices ORDER BY id").all();
    expect(remaining.results).toEqual([{ id: "device-live" }, { id: "device-signing-in" }]);
    expect(await countOf("auth_session")).toBe(1);
    expect(await countOf("push_tokens")).toBe(0);
    expect(await countOf("users")).toBe(1);
  });

  it.each([
    [
      "a single statement",
      (repository: AuthRepository["Service"]) => repository.findAccountKey("h"),
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
