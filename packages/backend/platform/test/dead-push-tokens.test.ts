import { env } from "cloudflare:workers";
import { Schema } from "effect";
import { beforeEach, describe, expect, it } from "vitest";
import { NoteId, UserId } from "@billet/contracts-domain/ids";
import { Note } from "@billet/contracts-domain/note";
import { ProviderTokens, sendApns, type ApnsFetch } from "../src/apns-client.ts";
import { sendPushLane, type PushLaneDependencies } from "../src/apns-lanes.ts";
import { dropToken, tokensOf } from "../src/partner-push-tokens.ts";
import { resetDirectory } from "./directory-migrations.ts";

const bob = Schema.decodeUnknownSync(UserId)("user-bob");
const alice = Schema.decodeUnknownSync(UserId)("user-alice");
const noteId = Schema.decodeUnknownSync(NoteId)("note-1");
const note = Schema.decodeUnknownSync(Note)({
  _tag: "Text",
  id: noteId,
  author: alice,
  at: 1,
  text: "hi",
});

const seed = async () => {
  await env.DB.batch([
    env.DB.prepare("INSERT INTO users (id, created_at) VALUES ('user-bob', 1)"),
    ...["d1", "d2", "d3"].map((device) =>
      env.DB.prepare(
        "INSERT INTO devices (id, user_id, created_at) VALUES (?, 'user-bob', 1)",
      ).bind(device),
    ),
    ...[
      ["d1", "alert", "dead-410"],
      ["d2", "alert", "dead-bad"],
      ["d3", "alert", "live"],
      ["d1", "widget", "dead-410"],
    ].map(([device, kind, token]) =>
      env.DB.prepare(
        "INSERT INTO push_tokens (device_id, kind, environment, token, updated_at) VALUES (?, ?, 'production', ?, 1)",
      ).bind(device, kind, token),
    ),
  ]);
};

// A fake APNs: the answer for each device token.
const fakeApns =
  (answers: Record<string, { status: number; reason?: string }>): ApnsFetch =>
  async (url) => {
    const answer = answers[url.slice(url.lastIndexOf("/") + 1)] ?? { status: 200 };
    return new Response(
      answer.reason === undefined ? null : JSON.stringify({ reason: answer.reason }),
      {
        status: answer.status,
      },
    );
  };

const pem = async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
  ]);
  if (!("privateKey" in pair)) throw new Error("ECDSA makes a key pair");
  const exported = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  if (!(exported instanceof ArrayBuffer)) throw new Error("pkcs8 exports bytes");
  let binary = "";
  for (const byte of new Uint8Array(exported)) binary += String.fromCharCode(byte);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
};

describe("dead push tokens", () => {
  beforeEach(async () => {
    await resetDirectory();
    await seed();
  });

  it("are deleted when APNs answers 410, BadDeviceToken or Unregistered, and live ones stay", async () => {
    const key = await pem();
    const fetcher = fakeApns({
      "dead-410": { status: 410 },
      "dead-bad": { status: 400, reason: "BadDeviceToken" },
    });
    const tokens = new ProviderTokens(() => 1);
    const dependencies: PushLaneDependencies = {
      note: async () => note,
      reaction: async () => undefined,
      match: async () => undefined,
      guess: async () => undefined,
      riddle: async () => undefined,
      recipient: async () => bob,
      tokens: (user, kind) => tokensOf(env.DB, user, kind),
      dropToken: (token, kind) => dropToken(env.DB, token, kind),
      send: (push) => sendApns(push, { key, keyId: "K" }, tokens, fetcher),
      nowSeconds: () => 1,
    };

    expect(await sendPushLane({ noteId, lane: "AlertPush" }, dependencies)).toBe("Delivered");

    expect((await tokensOf(env.DB, bob, "alert")).map((row) => row.token)).toEqual(["live"]);
    // The same token under another kind is another registration and is not touched.
    expect((await tokensOf(env.DB, bob, "widget")).map((row) => row.token)).toEqual(["dead-410"]);
  });

  it("are deleted for Unregistered, and a lone dead token abandons the push", async () => {
    const key = await pem();
    const dependencies: PushLaneDependencies = {
      note: async () => note,
      reaction: async () => undefined,
      match: async () => undefined,
      guess: async () => undefined,
      riddle: async () => undefined,
      recipient: async () => bob,
      tokens: (user, kind) => tokensOf(env.DB, user, kind),
      dropToken: (token, kind) => dropToken(env.DB, token, kind),
      send: (push) =>
        sendApns(
          push,
          { key, keyId: "K" },
          new ProviderTokens(() => 1),
          fakeApns({ "dead-410": { status: 400, reason: "Unregistered" } }),
        ),
      nowSeconds: () => 1,
    };

    expect(await sendPushLane({ noteId, lane: "WidgetPush" }, dependencies)).toBe("Abandon");
    expect(await tokensOf(env.DB, bob, "widget")).toEqual([]);
    expect(await tokensOf(env.DB, bob, "alert")).toHaveLength(3);
  });
});
