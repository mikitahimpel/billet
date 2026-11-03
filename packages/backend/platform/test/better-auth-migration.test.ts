import { env, exports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";
import { sha256Hex } from "../src/hashed-session-tokens.ts";
import { applyDirectoryMigrations } from "./directory-migrations.ts";

// The migration to Better Auth, run the way a deploy runs it: the directory as it was, with real
// users signed in and paired, then the new migration on top. Nobody may be signed out by it.

const migration = "20261103191857_better_auth";
const day = 24 * 60 * 60 * 1000;
const now = Date.now();

const alice = {
  id: "user-alice",
  subject: "001.alice",
  device: "device-alice",
  token: "a".repeat(43),
};
const bob = { id: "user-bob", subject: "001.bob", device: "device-bob", token: "b".repeat(43) };
const expired = { device: "device-old", token: "o".repeat(43) };

const call = (path: string, token: string, init: RequestInit = {}) =>
  exports.default.fetch(
    new Request(`https://billet.test${path}`, {
      method: "GET",
      ...init,
      headers: { authorization: `Bearer ${token}`, ...init.headers },
    }),
  );

beforeAll(async () => {
  await applyDirectoryMigrations(migration);
  const applied = await env.DB.prepare("SELECT name FROM __alchemy_migrations").all<{
    name: string;
  }>();
  // This file's storage must start empty, or the migration under test has already run.
  expect(applied.results.map(({ name }) => name)).not.toContain(migration);

  const statements = [alice, bob].flatMap(({ id, subject, device }) => [
    env.DB.prepare("INSERT INTO users (id, apple_subject, created_at) VALUES (?, ?, ?)").bind(
      id,
      subject,
      now - 30 * day,
    ),
    env.DB.prepare("INSERT INTO devices (id, user_id, created_at) VALUES (?, ?, ?)").bind(
      device,
      id,
      now - 30 * day,
    ),
    env.DB.prepare("INSERT INTO pair_members (user_id, pair_id, created_at) VALUES (?, ?, ?)").bind(
      id,
      "pair-1",
      now - 29 * day,
    ),
  ]);
  const session = (device: string, token: string, expiresAt: number) =>
    sha256Hex(token).then((hash) =>
      env.DB.prepare(
        "INSERT INTO sessions (token_hash, device_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
      ).bind(hash, device, now - 30 * day, expiresAt),
    );
  await env.DB.batch([
    ...statements,
    env.DB.prepare("INSERT INTO devices (id, user_id, created_at) VALUES (?, ?, ?)").bind(
      expired.device,
      alice.id,
      now - 200 * day,
    ),
    await session(alice.device, alice.token, now + 60 * day),
    await session(bob.device, bob.token, now + 10 * day),
    await session(expired.device, expired.token, now - day),
    env.DB.prepare(
      "INSERT INTO push_tokens (device_id, kind, environment, token, updated_at) VALUES (?, 'alert', 'production', ?, 1)",
    ).bind(alice.device, "aa".repeat(32)),
  ]);

  await applyDirectoryMigrations();
});

describe("the move to Better Auth", () => {
  it("keeps everyone signed in, as the same user on the same device", async () => {
    for (const person of [alice, bob]) {
      const response = await call("/v1/account", person.token);
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ userId: person.id, linked: true });
    }
    const register = await call("/v1/devices/current/push-token", alice.token, {
      method: "PUT",
      body: JSON.stringify({ kind: "alert", environment: "production", token: "cc".repeat(32) }),
      headers: { "content-type": "application/json" },
    });
    expect(register.status).toBe(204);
    const tokens = await env.DB.prepare("SELECT device_id, token FROM push_tokens").all();
    expect(tokens.results).toEqual([{ device_id: alice.device, token: "cc".repeat(32) }]);
  });

  it("keeps the pair intact", async () => {
    const pair = await env.DB.prepare(
      "SELECT user_id, pair_id FROM pair_members ORDER BY user_id",
    ).all();
    expect(pair.results).toEqual([
      { user_id: alice.id, pair_id: "pair-1" },
      { user_id: bob.id, pair_id: "pair-1" },
    ]);
    // The pair's own routes still know both of them: unpairing needs the lookup.
    const flags = await call("/v1/flags", bob.token);
    expect(flags.status).toBe(200);
  });

  it("links each user to their Apple ID, with no token and no real email", async () => {
    const accounts = await env.DB.prepare(
      "SELECT user_id, provider_id, account_id, id_token FROM auth_account ORDER BY user_id",
    ).all();
    expect(accounts.results).toEqual([
      { user_id: alice.id, provider_id: "apple", account_id: alice.subject, id_token: null },
      { user_id: bob.id, provider_id: "apple", account_id: bob.subject, id_token: null },
    ]);
    const emails = await env.DB.prepare("SELECT email FROM auth_user").all<{ email: string }>();
    for (const { email } of emails.results) expect(email).toMatch(/@apple\.billet\.invalid$/);
  });

  it("keeps the expiry and only the hash of each session", async () => {
    const stored = JSON.stringify(
      (await env.DB.prepare("SELECT token, expires_at FROM auth_session").all()).results,
    );
    for (const person of [alice, bob]) {
      expect(stored).not.toContain(person.token);
      expect(stored).toContain(await sha256Hex(person.token));
    }
    expect(stored).toContain(new Date(now + 10 * day).toISOString());
  });

  it("still refuses a session that had expired", async () => {
    expect((await call("/v1/account", expired.token)).status).toBe(401);
  });

  it("drops the old session table and the subject column", async () => {
    const tables = await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sessions'",
    ).all();
    expect(tables.results).toEqual([]);
    const columns = await env.DB.prepare("SELECT name FROM pragma_table_info('users')").all();
    expect(columns.results).toEqual([{ name: "id" }, { name: "created_at" }]);
  });
});
