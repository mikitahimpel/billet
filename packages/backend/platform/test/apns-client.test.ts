import { describe, expect, it } from "vitest";
import {
  classify,
  ProviderTokens,
  providerTokenLifetimeSeconds,
  sendApns,
  topicOf,
  type ApnsPush,
} from "../src/apns-client.ts";
import { appleTeamId } from "../src/es256-jwt.ts";

/** A throwaway P-256 key in the `.p8` form APNs keys come in, made fresh for each test run. */
const throwawayKey = async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ]);
  if (!("privateKey" in pair)) throw new Error("ECDSA makes a key pair");
  const exported = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  if (!(exported instanceof ArrayBuffer)) throw new Error("pkcs8 exports bytes");
  const der = new Uint8Array(exported);
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
  return { pem, publicKey: pair.publicKey };
};

const fromBase64Url = (text: string) =>
  Uint8Array.from(atob(text.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0));
const decodePart = (part: string) => JSON.parse(new TextDecoder().decode(fromBase64Url(part)));

const push = (overrides: Partial<ApnsPush> = {}): ApnsPush => ({
  token: "ab".repeat(32),
  environment: "production",
  pushType: "alert",
  body: { aps: { alert: { title: "t", body: "b" } } },
  ...overrides,
});

describe("APNs provider tokens", () => {
  it("signs an ES256 token Apple can verify, for the team and the key", async () => {
    const { pem, publicKey } = await throwawayKey();
    const token = await new ProviderTokens(() => 1_700_000_000).token({
      key: pem,
      keyId: "KEY123",
    });
    const [header, claims, signature] = token.split(".");

    expect(decodePart(header!)).toEqual({ alg: "ES256", kid: "KEY123" });
    expect(decodePart(claims!)).toEqual({ iss: appleTeamId, iat: 1_700_000_000 });
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      fromBase64Url(signature!),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });

  it("reuses a token until it is due, and signs again after, for another key or a reset", async () => {
    const { pem } = await throwawayKey();
    let now = 1_000;
    const tokens = new ProviderTokens(() => now);
    const first = await tokens.token({ key: pem, keyId: "K1" });

    now += providerTokenLifetimeSeconds - 1;
    expect(await tokens.token({ key: pem, keyId: "K1" })).toBe(first);
    now += 1;
    const renewed = await tokens.token({ key: pem, keyId: "K1" });
    expect(renewed).not.toBe(first);
    expect(await tokens.token({ key: pem, keyId: "K2" })).not.toBe(renewed);

    const again = await tokens.token({ key: pem, keyId: "K2" });
    tokens.reset();
    now += 1;
    expect(await tokens.token({ key: pem, keyId: "K2" })).not.toBe(again);
  });
});

describe("APNs failures", () => {
  it.each([
    [200, "", "Delivered"],
    [410, "Unregistered", "Unregistered"],
    [400, "BadDeviceToken", "Unregistered"],
    [400, "DeviceTokenNotForTopic", "Unregistered"],
    [400, "BadEnvironmentKeyInToken", "Unregistered"],
    [403, "ExpiredProviderToken", "Retry"],
    [403, "InvalidProviderToken", "Retry"],
    [429, "TooManyRequests", "Retry"],
    [500, "InternalServerError", "Retry"],
    [503, "ServiceUnavailable", "Retry"],
    [400, "PayloadTooLarge", "Rejected"],
    [400, "BadTopic", "Rejected"],
    [413, "", "Rejected"],
  ])("status %i %s is %s", (status, reason, tag) => {
    expect(classify(status, reason)._tag).toBe(tag);
  });
});

describe("sending a push", () => {
  const capture = (status = 200, body: unknown = undefined) => {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const fetcher = async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return new Response(body === undefined ? null : JSON.stringify(body), { status });
    };
    return { calls, fetcher };
  };

  it.each([
    ["alert", "production", "https://api.push.apple.com", "com.ourio.app", "10"],
    [
      "widgets",
      "sandbox",
      "https://api.sandbox.push.apple.com",
      "com.ourio.app.push-type.widgets",
      "5",
    ],
    [
      "liveactivity",
      "production",
      "https://api.push.apple.com",
      "com.ourio.app.push-type.liveactivity",
      "10",
    ],
  ] as const)(
    "sends %s to %s with its topic and priority",
    async (pushType, environment, host, topic, priority) => {
      const { pem } = await throwawayKey();
      const { calls, fetcher } = capture();
      const result = await sendApns(
        push({ pushType, environment, collapseId: "note-1" }),
        { key: pem, keyId: "K" },
        new ProviderTokens(() => 1),
        fetcher,
      );

      expect(result).toEqual({ _tag: "Delivered" });
      expect(topicOf(pushType)).toBe(topic);
      expect(calls[0]?.url).toBe(`${host}/3/device/${"ab".repeat(32)}`);
      const headers = calls[0]?.init.headers as Record<string, string>;
      expect(headers["apns-push-type"]).toBe(pushType);
      expect(headers["apns-topic"]).toBe(topic);
      expect(headers["apns-priority"]).toBe(priority);
      expect(headers["apns-collapse-id"]).toBe("note-1");
      expect(headers.authorization).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    },
  );

  it("reads the reason APNs gives", async () => {
    const { pem } = await throwawayKey();
    const { fetcher } = capture(410, { reason: "Unregistered" });
    expect(
      await sendApns(push(), { key: pem, keyId: "K" }, new ProviderTokens(() => 1), fetcher),
    ).toEqual({
      _tag: "Unregistered",
      reason: "Unregistered",
    });
  });

  it("sends a token the first app registered again under its topic", async () => {
    const { pem } = await throwawayKey();
    const calls: Array<string> = [];
    const fetcher = async (_url: string, init: RequestInit) => {
      const topic = (init.headers as Record<string, string>)["apns-topic"] ?? "";
      calls.push(topic);
      return topic.startsWith("com.mikitahimpel.billet")
        ? new Response(null, { status: 200 })
        : new Response(JSON.stringify({ reason: "DeviceTokenNotForTopic" }), { status: 400 });
    };
    const result = await sendApns(
      push({ pushType: "widgets" }),
      { key: pem, keyId: "K" },
      new ProviderTokens(() => 1),
      fetcher,
    );
    expect(result).toEqual({ _tag: "Delivered" });
    expect(calls).toEqual([
      "com.ourio.app.push-type.widgets",
      "com.mikitahimpel.billet.push-type.widgets",
    ]);
  });

  it("drops a token that is for neither app", async () => {
    const { pem } = await throwawayKey();
    const { calls, fetcher } = capture(400, { reason: "DeviceTokenNotForTopic" });
    expect(
      await sendApns(push(), { key: pem, keyId: "K" }, new ProviderTokens(() => 1), fetcher),
    ).toEqual({ _tag: "Unregistered", reason: "DeviceTokenNotForTopic" });
    expect(calls).toHaveLength(2);
  });

  it("signs a new provider token after APNs calls the old one expired", async () => {
    const { pem } = await throwawayKey();
    let now = 1;
    const tokens = new ProviderTokens(() => now);
    const { calls, fetcher } = capture(403, { reason: "ExpiredProviderToken" });
    expect((await sendApns(push(), { key: pem, keyId: "K" }, tokens, fetcher))._tag).toBe("Retry");
    now += 1;
    await sendApns(push(), { key: pem, keyId: "K" }, tokens, fetcher);
    const auth = (i: number) => {
      const headers = calls[i]?.init.headers as Record<string, string> | undefined;
      return headers?.authorization;
    };
    expect(auth(0)).toBeDefined();
    expect(auth(1)).not.toBe(auth(0));
  });

  it("treats a network failure, or a key that does not import, as a retry", async () => {
    const down = async () => {
      throw new Error("connection reset");
    };
    const { pem } = await throwawayKey();
    expect(
      await sendApns(push(), { key: pem, keyId: "K" }, new ProviderTokens(() => 1), down),
    ).toEqual({
      _tag: "Retry",
      reason: "connection reset",
    });
    const { fetcher } = capture();
    expect(
      (
        await sendApns(
          push(),
          { key: "not a key", keyId: "K" },
          new ProviderTokens(() => 1),
          fetcher,
        )
      )._tag,
    ).toBe("Retry");
  });
});
