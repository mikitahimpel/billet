import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";
import { Effect, Layer, Redacted, Schema } from "effect";
import { SecureRandom, Signature } from "effect/crypto";
import { Base64Url } from "effect/encoding";
import { Jwk, Jws } from "effect/jose";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import {
  appleAudience,
  appleIssuer,
  appleKeysUrl,
} from "@billet/backend-auth/apple-identity-verifier";
import { limitRequest, limits } from "../src/rate-limit.ts";
import { testNowOf } from "./test-now.ts";
import { clientHeaders, mediaPath, routes } from "@billet/contracts-http-api/routes";
import { respondApi } from "../src/api-fetch.ts";
import { opaqueRef } from "@billet/backend-observability/opaque-ref";
import { FlagConfigRepositoryLive } from "../src/flag-config-repository-live.ts";
import { FlagConfigRepository } from "@billet/backend-flags/flag-config-repository";
import { configOf } from "@billet/backend-flags/flag-config";
import { testExperiments } from "./test-experiments.ts";
import { imageSizeLimit } from "@billet/backend-notes/notes-routes";
import { AuthChallengeResponse, SessionResponse } from "@billet/contracts-http-api/auth";
import { FlagsResponse } from "@billet/contracts-http-api/flags";
import { ClaimInviteResponse, CreateInviteResponse } from "@billet/contracts-http-api/invite";
import {
  ListNotesResponse,
  SendNoteResponse,
  UploadImageResponse,
} from "@billet/contracts-http-api/note";
import { CoinsResponse } from "@billet/contracts-http-api/coins";
import { InksResponse } from "@billet/contracts-http-api/inks";
import { inks as inkCatalog } from "@billet/contracts-domain/inks";
import { OnboardingResponse } from "@billet/contracts-http-api/onboarding";
import { resetDirectory } from "./directory-migrations.ts";
import { PurchaseResponse, PurchasesResponse } from "@billet/contracts-http-api/purchase";
import {
  makeChain,
  makeXcodeChain,
  notificationPayload,
  signJws,
  transactionPayload,
} from "@billet/backend-payments/test/app-store-signer";
import { waitFor } from "./demo-wait.ts";

const cryptoLayer = Signature.layerWebCrypto.pipe(Layer.provide(SecureRandom.layerWebCrypto));

const appleKeys = await Effect.runPromise(
  Effect.gen(function* () {
    const pair = yield* Jwk.generateKeyPair({ algorithm: "RS256", kid: "apple-1" });
    return {
      privateKey: yield* Jwk.importPrivate(pair.privateKey, "RS256"),
      publicJwk: pair.publicKey,
    };
  }).pipe(Effect.provide(cryptoLayer)),
);

// Better Auth and the Apple check run on the real clock here, so a token's times lie far from it.
const farAhead = Date.UTC(2100, 0, 1) / 1000;
const longAgo = Date.UTC(2020, 0, 1) / 1000;

const claims = (nonce: string, overrides: Record<string, unknown> = {}) =>
  new TextEncoder().encode(
    JSON.stringify({
      iss: appleIssuer,
      aud: appleAudience,
      sub: "subject-a",
      nonce,
      exp: farAhead,
      ...overrides,
    }),
  );

const identityToken = (nonce: string, overrides?: Record<string, unknown>) =>
  Effect.runPromise(
    Jws.sign(claims(nonce, overrides), appleKeys.privateKey).pipe(
      Effect.map(Redacted.value),
      Effect.provide(cryptoLayer),
    ),
  );

/** The Worker as deployed on `stage`, which decides the payments extras. */
const atStage = async (stage: string | undefined, request: Request) => {
  const ctx = createExecutionContext();
  const stageEnv = { ...env, ...(stage === undefined ? {} : { STAGE: stage }) };
  const response = await respondApi(request, stageEnv, ctx, testExperiments);
  await waitOnExecutionContext(ctx);
  return response;
};

const call = (path: string, init: RequestInit = {}) =>
  exports.default.fetch(new Request(`https://billet.test${path}`, { method: "POST", ...init }));

const json = (body: unknown, method = "POST", token?: string): RequestInit => ({
  method,
  body: JSON.stringify(body),
  headers: {
    "content-type": "application/json",
    ...(token === undefined ? {} : { authorization: `Bearer ${token}` }),
  },
});

const challenge = async () =>
  Schema.decodeUnknownSync(AuthChallengeResponse)(await (await call("/v1/auth/challenge")).json());

const signIn = async (overrides?: Record<string, unknown>) => {
  const { nonce } = await challenge();
  return {
    nonce,
    response: await call(
      "/v1/auth/apple",
      json({ identityToken: await identityToken(nonce, overrides) }),
    ),
  };
};

const signedIn = async () => {
  const { nonce, response } = await signIn();
  expect(response.status).toBe(200);
  return { nonce, session: Schema.decodeUnknownSync(SessionResponse)(await response.json()) };
};

const signedInAs = async (subject: string) => {
  const { response } = await signIn({ sub: subject });
  expect(response.status).toBe(200);
  return Schema.decodeUnknownSync(SessionResponse)(await response.json()).sessionToken;
};

const inviteFrom = async (token: string) => {
  const response = await call("/v1/invites", json({}, "POST", token));
  expect(response.status).toBe(200);
  return Schema.decodeUnknownSync(CreateInviteResponse)(await response.json()).code;
};

const claimWith = (token: string, code: string) =>
  call("/v1/invites/claim", json({ code }, "POST", token));

const pairRows = async () =>
  (await env.DB.prepare("SELECT pair_id FROM pair_members").all<{ pair_id: string }>()).results;

const tables = [
  "pair_events",
  "pair_flags",
  "flag_configs",
  "flag_changes",
  "pair_flag_overrides",
  "users",
  "devices",
  "auth_user",
  "auth_session",
  "auth_account",
  "auth_verification",
  "account_keys",
  "auth_challenges",
  "push_tokens",
  "invites",
  "pair_members",
  "partner_notices",
];

const everythingStored = async () =>
  JSON.stringify(
    await Promise.all(
      tables.map(async (table) => (await env.DB.prepare(`SELECT * FROM ${table}`).all()).results),
    ),
  );

const sha256Hex = async (text: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

const bearer = (token: string) => ({ authorization: `Bearer ${token}` });

const pairOf = async (first: string, second: string) => {
  const [owner, claimer] = [await signedInAs(first), await signedInAs(second)];
  const response = await claimWith(claimer, await inviteFrom(owner));
  expect(response.status).toBe(200);
  const { pairId } = Schema.decodeUnknownSync(ClaimInviteResponse)(await response.json());
  return { owner, claimer, pairId };
};

const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/** Starts as a PNG and holds every byte value, so any text decoding along the way would show. */
const pngBytes = Uint8Array.from([...pngSignature, ...Array.from({ length: 256 }, (_, i) => i)]);

const jpegBytes = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, ...pngBytes.subarray(8)]);
const ascii = (text: string) => [...text].map((character) => character.charCodeAt(0));
const heicBytes = Uint8Array.from([0, 0, 0, 0x18, ...ascii("ftypheic"), ...pngBytes.subarray(8)]);

const upload = (token: string, body: BodyInit = pngBytes) =>
  call("/v1/media", { body, headers: { ...bearer(token), "content-type": "image/png" } });

const uploaded = async (token: string, body: BodyInit = pngBytes) => {
  const response = await upload(token, body);
  expect(response.status).toBe(200);
  return Schema.decodeUnknownSync(UploadImageResponse)(await response.json()).image;
};

const readImage = (key: string, token: string) =>
  call(`/v1/media/${key}`, { method: "GET", headers: bearer(token) });

const photoShape = { width: 4032, height: 3024, preview: "LEHV6nWB2yk8pyo0adR*.7kCMdnj" };

const sendPhoto = (token: string, image: string, key: string = crypto.randomUUID()) =>
  call("/v1/notes", json({ _tag: "Photo", key, image, ...photoShape }, "POST", token));

const sendText = (
  token: string,
  note: { readonly text: string; readonly paper?: string; readonly ink?: string },
  key: string = crypto.randomUUID(),
) => call("/v1/notes", json({ _tag: "Text", key, ...note }, "POST", token));

const saveAnswer = (token: string, stepId: string, answer: unknown, answeredAt = 1_000) =>
  call(
    "/v1/onboarding/answers",
    json({ version: "2026-11-04", stepId, answer, answeredAt }, "POST", token),
  );

const sentPhoto = async (token: string) => {
  const response = await sendPhoto(token, await uploaded(token));
  expect(response.status).toBe(200);
  const { note } = Schema.decodeUnknownSync(SendNoteResponse)(await response.json());
  if (note._tag !== "Photo") throw new Error(`expected a photo, got ${note._tag}`);
  return note;
};

const entriesFor = async (token: string, query = "") => {
  const response = await call(`/v1/notes${query}`, { method: "GET", headers: bearer(token) });
  expect(response.status).toBe(200);
  return Schema.decodeUnknownSync(ListNotesResponse)(await response.json()).notes;
};

const historyFor = async (token: string, query = "") =>
  (await entriesFor(token, query)).map(({ note }) => note);

const imageSizeInBytes = Number(imageSizeLimit);

const appleFetch = vi.fn<typeof fetch>();

beforeAll(() => {
  vi.stubGlobal("fetch", appleFetch);
});

beforeEach(async () => {
  await resetDirectory();
  appleFetch.mockReset();
  appleFetch.mockImplementation(async (input) => {
    expect(String(input)).toBe(appleKeysUrl);
    await new Promise((resolve) => setTimeout(resolve, 20));
    return Response.json({ keys: [appleKeys.publicJwk] });
  });
});

describe("the Api Worker", () => {
  it("still answers the deploy smoke test outside /v1/", async () => {
    const response = await exports.default.fetch("https://billet.test/");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ service: "billet-api", status: "ok" });
  });

  it("answers 404 for an unknown /v1/ route", async () => {
    expect((await call("/v1/nothing")).status).toBe(404);
  });

  it("keeps only hashes of the session token and the nonce in D1", async () => {
    expect(await everythingStored()).not.toContain((await challenge()).nonce);

    const { nonce, session } = await signedIn();
    const stored = await everythingStored();
    expect(stored).not.toContain(session.sessionToken);
    expect(stored).not.toContain(nonce);

    const rows = await env.DB.prepare("SELECT token FROM auth_session").all();
    expect(rows.results).toEqual([{ token: await sha256Hex(session.sessionToken) }]);
  });

  it("opens an anonymous account from a key, and the key brings it back", async () => {
    const accountKey = "k".repeat(43);
    const open = async () => {
      const response = await call("/v1/auth/anonymous", json({ accountKey }));
      expect(response.status).toBe(200);
      return Schema.decodeUnknownSync(SessionResponse)(await response.json());
    };
    const first = await open();
    const second = await open();
    expect(second.userId).toBe(first.userId);
    expect(second.deviceId).not.toBe(first.deviceId);

    const stored = await everythingStored();
    expect(stored).not.toContain(accountKey);
    expect(stored).not.toContain(first.sessionToken);
    expect(stored).not.toContain(second.sessionToken);
    const account = await call("/v1/account", {
      method: "GET",
      headers: { authorization: `Bearer ${first.sessionToken}` },
    });
    expect(await account.json()).toEqual({ userId: first.userId, linked: false });
  });

  it("links an anonymous account to Apple, keeping the user, and Apple restores it", async () => {
    const anonymous = Schema.decodeUnknownSync(SessionResponse)(
      await (await call("/v1/auth/anonymous", json({ accountKey: "a".repeat(43) }))).json(),
    );
    const owner = await signedInAs("subject-owner");
    expect((await claimWith(anonymous.sessionToken, await inviteFrom(owner))).status).toBe(200);

    const { nonce } = await challenge();
    const linked = await call(
      "/v1/auth/apple/link",
      json(
        { identityToken: await identityToken(nonce, { sub: "subject-linked" }) },
        "POST",
        anonymous.sessionToken,
      ),
    );
    expect(linked.status).toBe(200);
    expect(await linked.json()).toEqual({ userId: anonymous.userId, linked: true });

    // A new phone with neither the key nor the session: Sign in with Apple finds the same user,
    // still in the same pair.
    const restored = Schema.decodeUnknownSync(SessionResponse)(
      await (await signIn({ sub: "subject-linked" })).response.json(),
    );
    expect(restored.userId).toBe(anonymous.userId);
    expect((await pairRows()).length).toBe(2);
    expect(
      (await env.DB.prepare("SELECT id_token, access_token FROM auth_account").all()).results,
    ).toEqual([
      { id_token: null, access_token: null },
      { id_token: null, access_token: null },
    ]);
  });

  it("refuses to link an Apple ID that another account has", async () => {
    await signedInAs("subject-taken");
    const anonymous = Schema.decodeUnknownSync(SessionResponse)(
      await (await call("/v1/auth/anonymous", json({ accountKey: "b".repeat(43) }))).json(),
    );
    const { nonce } = await challenge();
    const response = await call(
      "/v1/auth/apple/link",
      json(
        { identityToken: await identityToken(nonce, { sub: "subject-taken" }) },
        "POST",
        anonymous.sessionToken,
      ),
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ _tag: "AppleIdInUse" });
  });

  it("forgets a signed-out device and its push tokens", async () => {
    const { session } = await signedIn();
    const register = await call(
      "/v1/devices/current/push-token",
      json(
        { kind: "alert", environment: "production", token: "aa".repeat(32) },
        "PUT",
        session.sessionToken,
      ),
    );
    expect(register.status).toBe(204);
    await call("/v1/auth/sign-out", {
      headers: { authorization: `Bearer ${session.sessionToken}` },
    });
    expect(await env.DB.prepare("SELECT * FROM push_tokens").first()).toBeNull();
    expect(await env.DB.prepare("SELECT * FROM devices").first()).toBeNull();
    expect(await env.DB.prepare("SELECT * FROM auth_session").first()).toBeNull();
  });

  it("registers a device's push token and replaces it", async () => {
    const { session } = await signedIn();
    const register = (token: string) =>
      call(
        "/v1/devices/current/push-token",
        json({ kind: "alert", environment: "production", token }, "PUT", session.sessionToken),
      );

    expect((await register("aa".repeat(32))).status).toBe(204);
    expect((await register("bb".repeat(32))).status).toBe(204);

    const rows = await env.DB.prepare("SELECT device_id, kind, token FROM push_tokens").all();
    expect(rows.results).toEqual([
      { device_id: session.deviceId, kind: "alert", token: "bb".repeat(32) },
    ]);
  });

  it("revokes the session on sign-out", async () => {
    const { session } = await signedIn();
    const signOut = () =>
      call("/v1/auth/sign-out", {
        headers: { authorization: `Bearer ${session.sessionToken}` },
      });
    expect((await signOut()).status).toBe(204);
    expect((await signOut()).status).toBe(401);
  });

  it("pairs two signed-in users with a code, and keeps only its hash", async () => {
    const owner = await signedInAs("subject-owner");
    const claimer = await signedInAs("subject-claimer");
    const code = await inviteFrom(owner);

    const stored = await everythingStored();
    expect(stored).not.toContain(code);
    const rows = await env.DB.prepare("SELECT code_hash FROM invites").all();
    expect(rows.results).toEqual([{ code_hash: await sha256Hex(code) }]);

    const response = await claimWith(claimer, code);
    expect(response.status).toBe(200);
    const { pairId } = Schema.decodeUnknownSync(ClaimInviteResponse)(await response.json());
    expect(await pairRows()).toEqual([{ pair_id: pairId }, { pair_id: pairId }]);
    expect(await env.DB.prepare("SELECT * FROM invites").first()).toBeNull();
  });

  it("traces a request: one trace line with the route, its service and repository spans, and refs", async () => {
    const owner = await signedInAs("subject-owner");
    const claimer = await signedInAs("subject-claimer");
    const code = await inviteFrom(owner);
    const lines: Array<Record<string, unknown>> = [];
    const raw: Array<string> = [];
    const log = vi.spyOn(console, "log").mockImplementation((line: string) => {
      raw.push(line);
      lines.push(JSON.parse(line) as Record<string, unknown>);
    });
    const response = await call("/v1/invites/claim", {
      ...json({ code }, "POST", claimer),
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${claimer}`,
        "cf-ray": "8d2f0a1b2c3d4e5f-LHR",
      },
    });
    log.mockRestore();
    expect(response.status).toBe(200);
    const { pairId } = Schema.decodeUnknownSync(ClaimInviteResponse)(await response.json());

    const trace = lines.find(
      (line) => line["message"] === "trace" && line["span"] === "http.request",
    );
    expect(trace).toMatchObject({
      status: "ok",
      attributes: {
        "http.route": "POST /v1/invites/claim",
        "http.response.status_code": 200,
        "request.id": "8d2f0a1b2c3d4e5f-LHR",
        "pair.ref": opaqueRef(pairId),
      },
    });
    const spans = (trace?.["spans"] ?? []) as ReadonlyArray<Record<string, unknown>>;
    const names = spans.map((span) => span["name"]);
    expect(names).toEqual(
      expect.arrayContaining([
        "AuthService.authenticate",
        "AuthEngine.findSession",
        "PairingService.claimInvite",
        "PairingRepository.claimInvite",
      ]),
    );
    for (const span of spans) expect(span["spanId"]).toMatch(/^[0-9a-f]{16}$/);
    // The router's own server span would carry the raw URL; the request span replaces it.
    expect(names).not.toContain("POST");
    expect(JSON.stringify(trace)).not.toContain("url.");
    const output = raw.join("\n");
    for (const secret of [claimer, code, pairId]) expect(output).not.toContain(secret);
  });

  it("answers one success to two concurrent claims of one code", async () => {
    const owner = await signedInAs("subject-owner");
    const first = await signedInAs("subject-first");
    const second = await signedInAs("subject-second");
    const code = await inviteFrom(owner);

    const responses = await Promise.all([claimWith(first, code), claimWith(second, code)]);

    expect(responses.map(({ status }) => status).toSorted()).toEqual([200, 404]);
    expect(await pairRows()).toHaveLength(2);
  });

  it("refuses a paired user another code", async () => {
    const owner = await signedInAs("subject-owner");
    const claimer = await signedInAs("subject-claimer");
    const other = await signedInAs("subject-other");
    expect((await claimWith(claimer, await inviteFrom(owner))).status).toBe(200);

    const response = await claimWith(claimer, await inviteFrom(other));
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ _tag: "AlreadyPaired" });
  });

  it("clears the pair lookup on unpair, and the two can pair again", async () => {
    const owner = await signedInAs("subject-owner");
    const claimer = await signedInAs("subject-claimer");
    expect((await claimWith(claimer, await inviteFrom(owner))).status).toBe(200);

    const unpair = await call("/v1/pair", {
      method: "DELETE",
      headers: { authorization: `Bearer ${owner}` },
    });
    expect(unpair.status).toBe(204);
    expect(await pairRows()).toEqual([]);

    expect((await claimWith(owner, await inviteFrom(claimer))).status).toBe(200);
    expect(await pairRows()).toHaveLength(2);
  });

  it.each([
    ["expired", { exp: longAgo }],
    ["wrong-audience", { aud: "com.example.other" }],
  ])("refuses an %s token and stores no session", async (_, overrides) => {
    const { response } = await signIn(overrides);
    expect(response.status).toBe(401);
    expect(await env.DB.prepare("SELECT * FROM auth_session").first()).toBeNull();
  });

  it("refuses a tampered token and leaves its nonce live", async () => {
    const { nonce } = await challenge();
    const [header, , signature] = (await identityToken(nonce)).split(".");
    const forgedPayload = Base64Url.encode(claims(nonce, { sub: "someone-else" }));
    const tampered = [header, forgedPayload, signature].join(".");

    expect((await call("/v1/auth/apple", json({ identityToken: tampered }))).status).toBe(401);
    expect(await env.DB.prepare("SELECT * FROM users").first()).toBeNull();
    expect(
      (await call("/v1/auth/apple", json({ identityToken: await identityToken(nonce) }))).status,
    ).toBe(200);
  });

  it("refuses a replayed identity token", async () => {
    const { nonce } = await challenge();
    const token = await identityToken(nonce);
    expect((await call("/v1/auth/apple", json({ identityToken: token }))).status).toBe(200);
    expect((await call("/v1/auth/apple", json({ identityToken: token }))).status).toBe(401);
  });

  it("answers 503 and grants nothing when Apple's keys can't be read", async () => {
    appleFetch.mockRejectedValue(new Error("offline"));
    const { response } = await signIn();
    expect(response.status).toBe(503);
    expect(await env.DB.prepare("SELECT * FROM auth_session").first()).toBeNull();
  });

  it("serves concurrent sign-ins while no keys are loaded, each on its own fetch", async () => {
    const results = await Promise.all(Array.from({ length: 5 }, () => signIn()));
    expect(results.map(({ response }) => response.status)).toEqual([200, 200, 200, 200, 200]);
    expect(appleFetch).toHaveBeenCalledTimes(5);
    // One Apple ID, so one user, however the first sign-ins raced.
    const sessions = await Promise.all(
      results.map(async ({ response }) =>
        Schema.decodeUnknownSync(SessionResponse)(await response.json()),
      ),
    );
    expect(new Set(sessions.map(({ userId }) => userId)).size).toBe(1);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM auth_account").first("n")).toBe(1);
  });
});

describe("deleting an account", () => {
  const remove = (token: string, body: unknown = {}) =>
    call("/v1/account", json(body, "DELETE", token));
  const account = async (token: string) => {
    const response = await call("/v1/account", { method: "GET", headers: bearer(token) });
    return { status: response.status, body: await response.json() };
  };
  const count = async (sql: string, ...values: ReadonlyArray<string>) =>
    (
      await env.DB.prepare(sql)
        .bind(...values)
        .first<{ n: number }>()
    )?.n;

  it("deletes the user and all they own, unpairs the partner and tells them kindly", async () => {
    const accountKey = "d".repeat(43);
    const opened = await call("/v1/auth/anonymous", json({ accountKey }));
    const ana = Schema.decodeUnknownSync(SessionResponse)(await opened.json());
    const ben = await signedInAs("subject-ben");
    expect((await claimWith(ana.sessionToken, await inviteFrom(ben))).status).toBe(200);
    const [{ pair_id: pairId }] = (await pairRows()) as [{ pair_id: string }];
    await call(
      "/v1/devices/current/push-token",
      json(
        { kind: "alert", environment: "production", token: "dd".repeat(32) },
        "PUT",
        ana.sessionToken,
      ),
    );

    const anaNote = await sentPhoto(ana.sessionToken);
    expect((await saveAnswer(ana.sessionToken, "name", { _tag: "Text", text: "Ana" })).status).toBe(
      204,
    );
    expect((await saveAnswer(ben, "age", { _tag: "Skipped" })).status).toBe(204);
    const benNote = await sentPhoto(ben);
    const anaUnsent = await uploaded(ana.sessionToken);

    const response = await remove(ana.sessionToken);
    expect(response.status).toBe(204);

    // Gone: every row that names her, her session, and her images.
    for (const [table, column] of [
      ["users", "id"],
      ["auth_user", "id"],
      ["auth_session", "user_id"],
      ["auth_account", "user_id"],
      ["account_keys", "user_id"],
      ["devices", "user_id"],
      ["pair_members", "user_id"],
      ["invites", "owner_id"],
      ["pair_events", "user_id"],
      ["onboarding_answers", "user_id"],
    ] as const) {
      expect(
        await count(`SELECT COUNT(*) AS n FROM ${table} WHERE ${column} = ?`, ana.userId),
      ).toBe(0);
    }
    expect(await count("SELECT COUNT(*) AS n FROM push_tokens")).toBe(0);
    expect((await account(ana.sessionToken)).status).toBe(401);
    expect(await env.MEDIA.head(anaNote.image)).toBeNull();
    expect(await env.MEDIA.head(anaUnsent)).toBeNull();

    // Ben keeps his account, his note and its image, and is unpaired with a notice.
    expect(await env.MEDIA.head(benNote.image)).not.toBeNull();
    const room = await env.PAIR_ROOM.getByName(pairId).notes(0, 100);
    expect(room.map(({ note }) => note.id)).toEqual([benNote.id]);
    expect(await pairRows()).toEqual([]);
    const told = await account(ben);
    expect(told.status).toBe(200);
    expect(told.body).toMatchObject({
      linked: true,
      partnerLeft: { reason: "account-deleted", at: expect.any(Number) },
    });

    // Pairing again ends the notice; the same key opens a new, empty account.
    const cal = await signedInAs("subject-cal");
    expect((await claimWith(cal, await inviteFrom(ben))).status).toBe(200);
    expect((await account(ben)).body).not.toHaveProperty("partnerLeft");
    const again = Schema.decodeUnknownSync(SessionResponse)(
      await (await call("/v1/auth/anonymous", json({ accountKey }))).json(),
    );
    expect(again.userId).not.toBe(ana.userId);
  });

  it("deletes the user's JPEG and HEIC photos, sent or not", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const sent = await uploaded(owner, jpegBytes);
    expect((await sendPhoto(owner, sent)).status).toBe(200);
    const unsent = await uploaded(owner, heicBytes);
    const theirs = await uploaded(claimer, jpegBytes);
    expect([sent.endsWith(".jpg"), unsent.endsWith(".heic")]).toEqual([true, true]);

    expect((await remove(owner)).status).toBe(204);

    expect(await env.MEDIA.head(sent)).toBeNull();
    expect(await env.MEDIA.head(unsent)).toBeNull();
    expect(await env.MEDIA.head(theirs)).not.toBeNull();
  });

  it("deletes an unpaired account, and takes an Apple code without the key configured", async () => {
    const { session } = await signedIn();
    const response = await remove(session.sessionToken, { appleAuthorizationCode: "code" });
    expect(response.status).toBe(204);
    expect(await count("SELECT COUNT(*) AS n FROM users")).toBe(0);
    expect(await count("SELECT COUNT(*) AS n FROM auth_account")).toBe(0);
    // Apple's keys were read to sign in; nothing else went to Apple.
    expect(appleFetch.mock.calls.map(([input]) => String(input))).toEqual([appleKeysUrl]);
  });

  it("answers 401 without a session and deletes nothing", async () => {
    await signedIn();
    expect((await remove("x".repeat(43))).status).toBe(401);
    expect(await count("SELECT COUNT(*) AS n FROM users")).toBe(1);
  });
});

describe("note images", () => {
  it("returns identical bytes to both partners, stored under the couple's prefix", async () => {
    const { owner, claimer, pairId } = await pairOf("subject-owner", "subject-claimer");
    const key = await uploaded(owner);

    expect(key.startsWith(`pairs/${pairId}/`)).toBe(true);
    expect(await env.MEDIA.head(key)).not.toBeNull();

    for (const reader of [owner, claimer]) {
      const response = await readImage(key, reader);
      expect(response.status).toBe(200);
      expect(response.headers.get("content-type")).toBe("image/png");
      expect(response.headers.get("cache-control")).toBe("no-store");
      expect(new Uint8Array(await response.arrayBuffer())).toEqual(pngBytes);
    }
  });

  it.each([
    ["a JPEG", jpegBytes, ".jpg", "image/jpeg"],
    ["a HEIC", heicBytes, ".heic", "image/heic"],
  ])("stores %s with its extension and serves its content type", async (_, bytes, ext, type) => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const key = await uploaded(owner, bytes);

    expect(key.endsWith(ext)).toBe(true);
    expect((await env.MEDIA.head(key))?.httpMetadata?.contentType).toBe(type);
    const response = await readImage(key, claimer);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe(type);
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(bytes);
  });

  it("answers 404 to anyone outside the pair, the same as for a key that doesn't exist", async () => {
    const { owner, claimer, pairId } = await pairOf("subject-owner", "subject-claimer");
    const key = await uploaded(owner);
    const stranger = await signedInAs("subject-stranger");
    const otherCouple = await pairOf("subject-other-a", "subject-other-b");

    const missing = await readImage(`pairs/${pairId}/notes/missing.png`, owner);
    expect(missing.status).toBe(404);
    const body = await missing.json();

    for (const outsider of [stranger, otherCouple.owner, otherCouple.claimer]) {
      const response = await readImage(key, outsider);
      expect(response.status).toBe(404);
      expect(await response.json()).toEqual(body);
    }

    const unpair = await call("/v1/pair", { method: "DELETE", headers: bearer(claimer) });
    expect(unpair.status).toBe(204);
    expect((await readImage(key, claimer)).status).toBe(404);
    expect(await env.MEDIA.head(key)).not.toBeNull();
  });

  it("answers 401 without a session", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const key = await uploaded(owner);
    expect((await call(`/v1/media/${key}`, { method: "GET" })).status).toBe(401);
    expect((await call("/v1/media", { body: pngBytes })).status).toBe(401);
  });

  it("refuses an upload from a user with no partner", async () => {
    expect((await upload(await signedInAs("subject-alone"))).status).toBe(404);
  });

  it("refuses bytes that aren't a PNG, JPEG or HEIC, and an image over the limit", async () => {
    const { owner, pairId } = await pairOf("subject-owner", "subject-claimer");

    expect((await upload(owner, "not an image")).status).toBe(400);

    for (const signature of [pngSignature, [0xff, 0xd8, 0xff]]) {
      const oversized = new Uint8Array(imageSizeInBytes + 1);
      oversized.set(signature);
      expect((await upload(owner, oversized)).status).toBe(400);
    }

    const stored = await env.MEDIA.list({ prefix: `pairs/${pairId}/` });
    expect(stored.objects).toEqual([]);
  });
});

describe("notes", () => {
  it("opens the room on the first note and returns history in order, to both partners", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    expect(await historyFor(owner)).toEqual([]);

    const sent = [
      await sentPhoto(owner),
      await sentPhoto(claimer),
      await sentPhoto(owner),
      await sentPhoto(owner),
    ];

    expect(await historyFor(owner)).toEqual(sent);
    expect(await historyFor(claimer)).toEqual(sent);
  });

  it("orders concurrent first notes from both partners without losing one", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const notes = await Promise.all([sentPhoto(owner), sentPhoto(claimer), sentPhoto(owner)]);
    const history = await historyFor(owner);
    expect(history.map(({ id }) => id).toSorted()).toEqual(notes.map(({ id }) => id).toSorted());
  });

  it("pages through history from a sequence number", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const sent = [
      await sentPhoto(owner),
      await sentPhoto(owner),
      await sentPhoto(owner),
      await sentPhoto(owner),
    ];
    expect(await historyFor(owner, "?limit=2")).toEqual(sent.slice(0, 2));
    expect(await historyFor(owner, "?after=2&limit=1")).toEqual(sent.slice(2, 3));
    expect(await historyFor(owner, "?after=4")).toEqual([]);
  });

  it("numbers each entry, so a client pages with only the response", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const sent = [
      await sentPhoto(owner),
      await sentPhoto(claimer),
      await sentPhoto(owner),
      await sentPhoto(owner),
      await sentPhoto(claimer),
    ];
    const seen: Array<{ seq: number; id: string }> = [];
    let after = 0;
    for (;;) {
      const page = await entriesFor(owner, `?after=${after}&limit=2`);
      if (page.length === 0) break;
      seen.push(...page.map(({ seq, note }) => ({ seq, id: note.id })));
      after = page[page.length - 1]?.seq ?? after;
    }
    expect(seen).toEqual(sent.map(({ id }, index) => ({ seq: index + 1, id })));
  });

  it("stores one note for a key sent again, and answers with the first", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const image = await uploaded(owner);
    const key = crypto.randomUUID();
    const read = async (response: Response) => {
      expect(response.status).toBe(200);
      return Schema.decodeUnknownSync(SendNoteResponse)(await response.json()).note;
    };
    const first = await read(await sendPhoto(owner, image, key));
    const again = await read(await sendPhoto(owner, image, key));
    expect(again).toEqual(first);
    expect(await historyFor(claimer)).toEqual([first]);
    // The partner may use the same key for a note of their own.
    const theirs = await read(await sendPhoto(claimer, await uploaded(claimer), key));
    expect(theirs.id).not.toBe(first.id);
    expect(await historyFor(owner)).toEqual([first, theirs]);
  });

  it("stores one note when a key is sent twice at once", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const image = await uploaded(owner);
    const key = crypto.randomUUID();
    const responses = await Promise.all([
      sendPhoto(owner, image, key),
      sendPhoto(owner, image, key),
      sendPhoto(owner, image, key),
    ]);
    expect(responses.map((response) => response.status)).toEqual([200, 200, 200]);
    expect(await historyFor(owner)).toHaveLength(1);
  });

  it.each(["", "not-a-uuid", "6f1c2d3e4a5b4c6d8e7f0a1b2c3d4e5f"])(
    "refuses the key %j",
    async (key) => {
      const { owner } = await pairOf("subject-owner", "subject-claimer");
      const response = await sendPhoto(owner, await uploaded(owner), key);
      expect(response.status).toBe(400);
    },
  );

  it("refuses a note with no key", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const image = await uploaded(owner);
    const response = await call("/v1/notes", json({ _tag: "Photo", image }, "POST", owner));
    expect(response.status).toBe(400);
  });

  it.each(["?limit=-1", "?limit=0", "?limit=101", "?limit=two", "?after=-1", "?after=1.5"])(
    "refuses the query %s",
    async (query) => {
      const { owner } = await pairOf("subject-owner", "subject-claimer");
      const response = await call(`/v1/notes${query}`, { method: "GET", headers: bearer(owner) });
      expect(response.status).toBe(400);
    },
  );

  it("keeps each couple's history to itself", async () => {
    const one = await pairOf("subject-one-a", "subject-one-b");
    const two = await pairOf("subject-two-a", "subject-two-b");
    const note = await sentPhoto(one.owner);

    expect(await historyFor(one.claimer)).toEqual([note]);
    expect(await historyFor(two.owner)).toEqual([]);
  });

  it("answers 404 to a user with no partner", async () => {
    const stranger = await signedInAs("subject-stranger");
    const response = await call("/v1/notes", { method: "GET", headers: bearer(stranger) });
    expect(response.status).toBe(404);
  });

  it("refuses a note whose image isn't in the couple's prefix", async () => {
    const one = await pairOf("subject-one-a", "subject-one-b");
    const two = await pairOf("subject-two-a", "subject-two-b");

    const theirs = await sendPhoto(two.owner, await uploaded(one.owner));
    expect(theirs.status).toBe(404);
    const unknown = await sendPhoto(one.owner, `pairs/${one.pairId}/notes/never-uploaded.png`);
    expect(unknown.status).toBe(404);
    expect(await historyFor(one.owner)).toEqual([]);
    expect(await historyFor(two.owner)).toEqual([]);
  });

  it("keeps both renditions of a drawing, and refuses a compact one over budget", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const image = await uploaded(owner);
    const drawing = (points: ReadonlyArray<number>) =>
      call(
        "/v1/notes",
        json(
          {
            _tag: "Drawing",
            key: crypto.randomUUID(),
            image,
            compact: { version: 1, strokes: [{ color: "#2A1A1C", width: 3, points }] },
          },
          "POST",
          owner,
        ),
      );

    expect((await drawing(Array.from({ length: 1_600 }, () => 1))).status).toBe(400);
    expect((await drawing([10, 20, 30, 40])).status).toBe(200);

    const [note] = await historyFor(owner);
    expect(note).toMatchObject({
      _tag: "Drawing",
      image,
      compact: { strokes: [{ points: [10, 20, 30, 40] }] },
    });
    expect(note).not.toHaveProperty("paper");
  });

  it("keeps a drawing's paper", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const image = await uploaded(owner);
    const compact = { version: 1, strokes: [{ color: "#2A1A1C", width: 3, points: [1, 2] }] };
    const sent = await call(
      "/v1/notes",
      json(
        { _tag: "Drawing", key: crypto.randomUUID(), image, compact, paper: "sage" },
        "POST",
        owner,
      ),
    );
    expect(sent.status).toBe(200);
    const [note] = await historyFor(owner);
    expect(note).toMatchObject({ _tag: "Drawing", image, paper: "sage" });
  });

  it("stores a text note with its paper, and gives it to both partners as written", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const response = await sendText(owner, { text: "miss you already 💛", paper: "butter" });
    expect(response.status).toBe(200);
    const { note } = Schema.decodeUnknownSync(SendNoteResponse)(await response.json());
    expect(note).toMatchObject({ _tag: "Text", text: "miss you already 💛", paper: "butter" });
    expect(note).not.toHaveProperty("image");

    expect((await sendText(claimer, { text: "home soon" })).status).toBe(200);
    const history = await historyFor(claimer);
    expect(history.map((n) => n._tag)).toEqual(["Text", "Text"]);
    expect(history[0]).toEqual(note);
    expect(history[1]).not.toHaveProperty("paper");
    expect(await historyFor(owner)).toEqual(history);
  });

  it("writes a text note in the free ink, and refuses an ink the pair has not bought", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const bare = await sendText(owner, { text: "hi" });
    expect(bare.status).toBe(200);
    expect(Schema.decodeUnknownSync(SendNoteResponse)(await bare.json()).note).toMatchObject({
      ink: "ink-graphite",
    });
    const refused = await sendText(claimer, { text: "hi", ink: "ink-rose" });
    expect(refused.status).toBe(400);
    expect(await refused.json()).toEqual({ _tag: "InkNotOwned", ink: "ink-rose" });
    expect((await sendText(owner, { text: "hi", ink: "ink-nope" })).status).toBe(400);
    expect(await historyFor(owner)).toHaveLength(1);

    const inks = await call("/v1/inks", { method: "GET", headers: bearer(claimer) });
    expect(inks.status).toBe(200);
    expect(inks.headers.get("cache-control")).toBe("no-store");
    expect(Schema.decodeUnknownSync(InksResponse)(await inks.json())).toEqual({
      inks: inkCatalog,
      owned: ["ink-graphite"],
    });
  });

  it("shows the pair's wallet, and refuses a buy it cannot pay for or already owns", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const coins = await call("/v1/coins", { method: "GET", headers: bearer(claimer) });
    expect(coins.status).toBe(200);
    expect(coins.headers.get("cache-control")).toBe("no-store");
    // Reading the wallet opens the pair's room, with its welcome coins.
    expect(Schema.decodeUnknownSync(CoinsResponse)(await coins.json())).toMatchObject({
      balance: 560,
      entries: [{ id: "gift:welcome", kind: "gift", amount: 560 }],
    });
    const order = (item: string) =>
      call("/v1/shop/orders", {
        method: "POST",
        headers: { ...bearer(owner), "content-type": "application/json" },
        body: JSON.stringify({ id: crypto.randomUUID(), offer: { _tag: "Item", item } }),
      });
    // Neither piece is ever a deal: the tower leaves 20 of the 560.
    expect((await order("tower")).status).toBe(200);
    const buy = (item: string) =>
      call("/v1/shop/buy", {
        method: "POST",
        headers: { ...bearer(owner), "content-type": "application/json" },
        body: JSON.stringify({ id: crypto.randomUUID(), item }),
      });
    const broke = await buy("ink-rose");
    expect(broke.status).toBe(409);
    expect(await broke.json()).toEqual({ _tag: "NotEnoughCoins", needed: 60, have: 20 });
    const free = await buy("ink-graphite");
    expect(free.status).toBe(409);
    expect(await free.json()).toEqual({ _tag: "AlreadyOwned", itemId: "ink-graphite" });
    expect((await buy("ink-nope")).status).toBe(400);
    const badPage = await call("/v1/coins?limit=0", { method: "GET", headers: bearer(owner) });
    expect(badPage.status).toBe(400);
  });

  it("opens the day's gift once for the pair, and pays an app earn once per ref", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const post = (token: string, path: string, body: unknown) =>
      call(path, {
        method: "POST",
        headers: { ...bearer(token), "content-type": "application/json" },
        body: JSON.stringify(body),
      });
    const gift = await post(owner, "/v1/shop/gift", { utcOffsetSeconds: 3600 });
    expect(gift.status).toBe(200);
    const opened = await gift.json();
    expect(await (await post(claimer, "/v1/shop/gift", { utcOffsetSeconds: 3600 })).json()).toEqual(
      opened,
    );
    const earn = { event: { _tag: "WishReceived", wish: "wish-1" } };
    const first = await (await post(owner, "/v1/coins/earn", earn)).json();
    expect(first).toMatchObject({ entry: { id: "earn:wish:wish-1", amount: 20 } });
    expect(await (await post(claimer, "/v1/coins/earn", earn)).json()).toEqual(first);
    const bonus = await post(owner, "/v1/shop/bonus", { collection: "cozy-autumn" });
    expect(bonus.status).toBe(409);
    expect(await bonus.json()).toEqual({ _tag: "CollectionIncomplete", collection: "cozy-autumn" });
  });

  it("refuses a text note that is blank, over 120 characters or on an unknown paper", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    expect((await sendText(owner, { text: "   " })).status).toBe(400);
    expect((await sendText(owner, { text: "a".repeat(121) })).status).toBe(400);
    expect((await sendText(owner, { text: "hi", paper: "mint" })).status).toBe(400);
    expect((await sendText(owner, { text: "💛".repeat(120) })).status).toBe(200);
    expect(await historyFor(owner)).toHaveLength(1);
  });

  it("stores one text note for a key sent again", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const key = crypto.randomUUID();
    const first = await sendText(owner, { text: "once" }, key);
    const again = await sendText(owner, { text: "once" }, key);
    expect(await again.json()).toEqual(await first.json());
    expect(await historyFor(owner)).toHaveLength(1);
  });
});

describe("onboarding", () => {
  const anonymous = async (letter: string) => {
    const opened = await call("/v1/auth/anonymous", json({ accountKey: letter.repeat(43) }));
    expect(opened.status).toBe(200);
    return Schema.decodeUnknownSync(SessionResponse)(await opened.json());
  };
  const rowsOf = async (userId: string) =>
    (
      await env.DB.prepare(
        "SELECT step_id, kind, option_ids, text, answered_at FROM onboarding_answers WHERE user_id = ? ORDER BY step_id",
      )
        .bind(userId)
        .all()
    ).results;

  it("serves the questions to the anonymous account from first launch", async () => {
    const { sessionToken } = await anonymous("o");
    const response = await call("/v1/onboarding", { method: "GET", headers: bearer(sessionToken) });
    expect(response.status).toBe(200);
    const body = Schema.decodeUnknownSync(OnboardingResponse)(await response.json());
    expect(body.steps.map((step) => step.id)).toEqual(["age", "pronouns", "name", "goals"]);
    expect((await call("/v1/onboarding", { method: "GET" })).status).toBe(401);
  });

  it("stores each step once, a skip too, and keeps the later of two answers", async () => {
    const { sessionToken, userId } = await anonymous("p");
    const save = (stepId: string, answer: unknown, at?: number) =>
      saveAnswer(sessionToken, stepId, answer, at).then((response) => response.status);
    expect(await save("age", { _tag: "Single", option: "age-25-34" })).toBe(204);
    expect(await save("goals", { _tag: "Multi", options: ["widgets", "raise-pet"] })).toBe(204);
    expect(await save("pronouns", { _tag: "Skipped" })).toBe(204);
    expect(await save("cat_coat", { _tag: "Single", option: "grey" })).toBe(204);
    expect(await save("cat_name", { _tag: "Text", text: "Biscuit" }, 2_000)).toBe(204);
    // A queued older retry arrives late and changes nothing.
    expect(await save("cat_name", { _tag: "Skipped" }, 1_500)).toBe(204);
    expect(await save("age", { _tag: "Single", option: "age-99" })).toBe(400);

    expect(await rowsOf(userId)).toEqual([
      {
        step_id: "age",
        kind: "Single",
        option_ids: '["age-25-34"]',
        text: null,
        answered_at: 1_000,
      },
      {
        step_id: "cat_coat",
        kind: "Single",
        option_ids: '["grey"]',
        text: null,
        answered_at: 1_000,
      },
      { step_id: "cat_name", kind: "Text", option_ids: null, text: "Biscuit", answered_at: 2_000 },
      {
        step_id: "goals",
        kind: "Multi",
        option_ids: '["widgets","raise-pet"]',
        text: null,
        answered_at: 1_000,
      },
      { step_id: "pronouns", kind: "Skipped", option_ids: null, text: null, answered_at: 1_000 },
    ]);
  });
});

describe("Analytics Engine", () => {
  const report = async (token: string, dataset: AnalyticsEngineDataset | undefined) => {
    const ctx = createExecutionContext();
    const response = await respondApi(
      new Request("https://billet.test/v1/events", {
        method: "POST",
        headers: {
          ...bearer(token),
          "content-type": "application/json",
          [clientHeaders.appVersion]: "1.0.0+12",
          [clientHeaders.os]: "iOS 26.1",
          "cf-connecting-ip": "203.0.113.9",
        },
        body: JSON.stringify({ events: ["AppOpened", "WidgetAdded"] }),
      }),
      { ...env, ...(dataset === undefined ? {} : { EVENTS: dataset }) },
      ctx,
      testExperiments,
    );
    await waitOnExecutionContext(ctx);
    return response;
  };

  it("writes each accepted event with the pair hashed, its variants, build and system", async () => {
    const { owner, pairId } = await pairOf("subject-a", "subject-b");
    const written: Array<AnalyticsEngineDataPoint> = [];
    const response = await report(owner, { writeDataPoint: (point) => void written.push(point!) });
    expect(response.status).toBe(204);

    const hash = (await sha256Hex(`billet-pair:${pairId}`)).slice(0, 16);
    const stored = (
      await env.DB.prepare("SELECT experiment_key, variant FROM pair_flags WHERE pair_id = ?")
        .bind(pairId)
        .all<{ experiment_key: string; variant: string }>()
    ).results;
    const variants = stored
      .map((row) => `${row.experiment_key}=${row.variant}`)
      .toSorted()
      .join(",");
    expect(variants).not.toBe("");
    expect(written).toEqual(
      ["AppOpened", "WidgetAdded"].map((name) => ({
        indexes: [hash],
        blobs: [name, hash, variants, "1.0.0+12", "iOS 26.1", ""],
        doubles: [1, 0],
      })),
    );
    const text = JSON.stringify(written);
    for (const secret of [pairId, owner, "subject-a", "203.0.113.9"]) {
      expect(text).not.toContain(secret);
    }
    // The D1 counts are still kept: the funnel reads them.
    expect(await everythingStored()).toContain("WidgetAdded");
  });

  it("still counts in D1 when no dataset is bound, and when a write throws", async () => {
    const token = await signedInAs("subject-c");
    expect((await report(token, undefined)).status).toBe(204);
    const throwing = {
      writeDataPoint: () => {
        throw new Error("dataset down");
      },
    };
    expect((await report(token, throwing)).status).toBe(204);
    const rows = (
      await env.DB.prepare("SELECT count FROM pair_events WHERE name = 'AppOpened'").all<{
        count: number;
      }>()
    ).results;
    expect(rows.map(({ count }) => count)).toEqual([2]);
  });
});

describe("routes from the contracts", () => {
  const send = (method: string, path: string) =>
    exports.default.fetch(new Request(`https://billet.test${path}`, { method }));
  const concrete = (path: string) => (path.endsWith("*") ? mediaPath("pairs/p/notes/n.png") : path);

  // The mock purchase route exists only on the dev stage; the payments tests check the others.
  const onDev = (method: string, path: string) =>
    atStage("dev", new Request(`https://billet.test${path}`, { method }));

  it.each(Object.entries(routes))("%s is served at its method and path", async (name, route) => {
    // Whatever the answer is, it is not "no such route".
    const response =
      name === "mockPurchase"
        ? await onDev(route.method, route.path)
        : await send(route.method, concrete(route.path));
    expect(response.status).not.toBe(404);
  });

  it.each(Object.entries(routes))("%s is is not served under another path", async (_, route) => {
    const moved = concrete(route.path).replace("/v1/", "/v1/moved/");
    expect((await send(route.method, moved)).status).toBe(404);
  });
});

describe("rate limits in the Worker", () => {
  const challenge = () =>
    new Request("https://billet.test/v1/auth/challenge", {
      method: "POST",
      headers: { "cf-connecting-ip": "203.0.113.50" },
    });

  it("answers 429 past the limit on a limited route, and not on others", async () => {
    // The counting is rate-limit.test.ts's; this pins down that the Worker applies it. All but the
    // last allowed request are counted straight into D1, at the Worker's instant (TEST_NOW):
    // thirty challenges through the Worker took close to the 5 s timeout on CI.
    for (let i = 1; i < limits.auth; i++) {
      expect(await limitRequest(challenge(), env.DB, testNowOf(env))).toBeUndefined();
    }
    expect((await exports.default.fetch(challenge())).status).toBe(200);
    expect((await exports.default.fetch(challenge())).status).toBe(429);
    expect((await call("/v1/notes")).status).not.toBe(429);
  });
});

describe("what the Worker logs", () => {
  it("never writes a token, a code, a nonce or note content", async () => {
    const lines: string[] = [];
    const record = (...args: unknown[]) => {
      lines.push(
        args.map((arg) => (typeof arg === "string" ? arg : JSON.stringify(arg))).join(" "),
      );
    };
    const spies = (["log", "info", "warn", "error", "debug"] as const).map((level) =>
      vi.spyOn(console, level).mockImplementation(record),
    );

    const secrets: string[] = [];
    try {
      const { nonce } = await challenge();
      const identity = await identityToken(nonce);
      secrets.push(nonce, identity);
      const owner = await signedInAs("subject-owner");
      const claimer = await signedInAs("subject-claimer");
      secrets.push(owner, claimer);
      const code = await inviteFrom(owner);
      secrets.push(code);
      await claimWith(claimer, code);

      const image = await uploaded(owner);
      const marker = [4242, 4243, 4244, 4245];
      await call(
        "/v1/notes",
        json(
          {
            _tag: "Drawing",
            key: crypto.randomUUID(),
            image,
            compact: { version: 1, strokes: [{ color: "#2A1A1C", width: 3, points: marker }] },
          },
          "POST",
          owner,
        ),
      );
      secrets.push(marker.join(","));
      const words = "a private line for my partner only";
      await sendText(owner, { text: words, paper: "sky" });
      await sendText(owner, { text: `${words} ${"x".repeat(120)}` });
      secrets.push(words);

      // The failure paths are where a careless log would quote its input.
      const [header, , signature] = (await identityToken((await challenge()).nonce)).split(".");
      const forged = [header, Base64Url.encode(claims("x", { sub: "forged" })), signature].join(
        ".",
      );
      secrets.push(forged);
      await call("/v1/auth/apple", json({ identityToken: forged }));
      await call("/v1/notes", { method: "GET", headers: bearer("not-a-real-session-token") });
      secrets.push("not-a-real-session-token");
      await claimWith(claimer, "WRONGCODE1");
      appleFetch.mockRejectedValue(new Error(`offline ${owner}`));
      await signIn();
    } finally {
      for (const spy of spies) spy.mockRestore();
    }

    expect(lines.length).toBeGreaterThan(0);
    const output = lines.join("\n");
    for (const secret of secrets) expect(output).not.toContain(secret);
  });
});

describe("the couple's WebSocket", () => {
  type Frame = { readonly _tag: string; readonly [key: string]: unknown };
  const stroke = {
    color: "#2A1A1C",
    width: 3,
    points: [
      { x: 1, y: 2 },
      { x: 3, y: 4 },
    ],
  };

  const openSocket = async (token: string) => {
    const response = await exports.default.fetch(
      new Request("https://billet.test/v1/socket", {
        headers: { upgrade: "websocket", ...bearer(token) },
      }),
    );
    expect(response.status).toBe(101);
    const ws = response.webSocket!;
    const frames: Frame[] = [];
    ws.addEventListener("message", (event) => {
      frames.push(JSON.parse(event.data as string));
    });
    ws.accept();
    const resume = (lastSeq: number) => {
      ws.send(JSON.stringify({ _tag: "Resume", lastSeq }));
    };
    const ofTag = (tag: string) => frames.filter((f) => f._tag === tag);
    const seqs = () => ofTag("NoteReceived").map((f) => f["seq"]);
    return { ws, frames, resume, ofTag, seqs };
  };

  const until = (check: () => boolean, what: string) => waitFor(check, what);

  it("refuses a caller without a live session, without a partner or without an upgrade", async () => {
    const fetchSocket = (headers: Record<string, string>) =>
      exports.default.fetch(new Request("https://billet.test/v1/socket", { headers }));
    expect((await fetchSocket({ upgrade: "websocket" })).status).toBe(401);
    expect((await fetchSocket({ upgrade: "websocket", ...bearer("nonsense") })).status).toBe(401);
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    expect((await fetchSocket(bearer(owner))).status).toBe(426);
    const alone = await signedInAs("subject-alone");
    expect((await fetchSocket({ upgrade: "websocket", ...bearer(alone) })).status).toBe(404);
  });

  it("sends stored notes on resume, then new ones as they are stored", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    await sentPhoto(owner);
    await sentPhoto(owner);
    const partner = await openSocket(claimer);
    partner.resume(0);
    await until(() => partner.seqs().length === 2, "the two stored notes");
    await sentPhoto(owner);
    await until(() => partner.seqs().length === 3, "the live note");
    expect(partner.seqs()).toEqual([1, 2, 3]);
  });

  it("delivers a text note live, words and paper included", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const partner = await openSocket(claimer);
    partner.resume(0);
    await sendText(owner, { text: "look outside 🌙", paper: "sky" });
    await until(() => partner.seqs().length === 1, "the text note");
    expect(partner.ofTag("NoteReceived")[0]).toMatchObject({
      seq: 1,
      note: { _tag: "Text", text: "look outside 🌙", paper: "sky" },
    });
  });

  it("gives no note before the client asks to resume", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    await sentPhoto(owner);
    const partner = await openSocket(claimer);
    await sentPhoto(owner);
    partner.resume(0);
    await until(() => partner.seqs().length === 2, "both notes after resume");
    expect(partner.seqs()).toEqual([1, 2]);
  });

  it("resumes after a dropped connection with no gap and no repeat", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    await sentPhoto(owner);
    const first = await openSocket(claimer);
    first.resume(0);
    await until(() => first.seqs().length === 1, "the first note");
    first.ws.close(1001);
    await sentPhoto(owner);
    await sentPhoto(owner);

    const again = await openSocket(claimer);
    again.resume(1);
    await until(() => again.seqs().length === 2, "the two missed notes");
    await sentPhoto(owner);
    await until(() => again.seqs().length === 3, "the next live note");
    expect(again.seqs()).toEqual([2, 3, 4]);
  });

  it("does not repeat a note when a resume races a new note", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    await sentPhoto(owner);
    const partner = await openSocket(claimer);
    partner.resume(0);
    await Promise.all([sentPhoto(owner), sentPhoto(owner), sentPhoto(owner)]);
    await until(() => partner.seqs().length >= 4, "all four notes");
    expect(partner.seqs()).toEqual([1, 2, 3, 4]);
  });

  it("relays a live stroke to the partner only", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const mine = await openSocket(owner);
    const theirs = await openSocket(claimer);
    mine.ws.send(JSON.stringify({ _tag: "Stroke", stroke }));
    await until(() => theirs.ofTag("Stroke").length === 1, "the stroke");
    expect(theirs.ofTag("Stroke")[0]).toMatchObject({ stroke, seq: 0 });
    mine.ws.send(JSON.stringify({ _tag: "Presence", state: "idle" }));
    await until(
      () => theirs.ofTag("Presence").length >= 1,
      "a later frame, so the stroke echo would have arrived",
    );
    expect(mine.ofTag("Stroke")).toEqual([]);
  });

  it("tells the partner when someone starts drawing and when they disconnect", async () => {
    const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
    const mine = await openSocket(owner);
    mine.ws.send(JSON.stringify({ _tag: "Presence", state: "drawing" }));
    const theirs = await openSocket(claimer);
    await until(() => theirs.ofTag("Presence").length === 1, "the presence on connect");
    expect(theirs.ofTag("Presence")[0]).toMatchObject({ state: "drawing" });

    mine.ws.close(1000);
    await until(() => theirs.ofTag("Presence").length === 2, "idle after disconnect");
    expect(theirs.ofTag("Presence")[1]).toMatchObject({ state: "idle" });
  });

  it("ignores frames it cannot read and ends a connection that sends a huge one", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const mine = await openSocket(owner);
    const closed = new Promise<number>((resolve) => {
      mine.ws.addEventListener("close", (event) => {
        resolve(event.code);
      });
    });
    mine.ws.send("not json");
    mine.ws.send(JSON.stringify({ _tag: "Unknown" }));
    mine.ws.send("x".repeat(70_000));
    expect(await closed).toBe(1009);
  });

  describe("flags", () => {
    const flagsFor = async (token: string) => {
      const response = await call("/v1/flags", { method: "GET", headers: bearer(token) });
      expect(response.status).toBe(200);
      expect(response.headers.get("cache-control")).toBe("no-store");
      return Schema.decodeUnknownSync(FlagsResponse)(await response.json()).flags;
    };

    const storedFlags = async () =>
      (
        await env.DB.prepare("SELECT pair_id, experiment_key, variant FROM pair_flags").all<{
          pair_id: string;
          experiment_key: string;
          variant: string;
        }>()
      ).results;

    it("needs a signed-in caller", async () => {
      expect((await call("/v1/flags", { method: "GET" })).status).toBe(401);
    });

    it("follows a configuration saved without a deploy: a kill, then version targeting", async () => {
      const { owner } = await pairOf("subject-cfg-a", "subject-cfg-b");
      expect((await flagsFor(owner)).map(({ key }) => key)).toContain("split");
      const save = (config: Record<string, unknown>, expectedVersion: number) =>
        Effect.runPromise(
          Effect.gen(function* () {
            const repository = yield* FlagConfigRepository;
            const split = testExperiments.find(({ key }) => key === "split");
            if (split === undefined) throw new Error("no split");
            return yield* repository.save({
              key: split.key,
              config: { ...configOf(split), ...config },
              expectedVersion,
              action: "edit",
              by: "owner@example.com",
              at: Date.UTC(2026, 9, 31, 22, 42),
            });
          }).pipe(Effect.provide(FlagConfigRepositoryLive(env.DB, caches.default))),
        );
      await save({ killed: true }, 0);
      expect((await flagsFor(owner)).map(({ key }) => key)).not.toContain("split");
      await save({ killed: false, targeting: { minAppVersion: "2.0" } }, 1);
      // The pair entered before the targeting, so it keeps its variant.
      expect((await flagsFor(owner)).map(({ key }) => key)).toContain("split");
      const newcomer = (await pairOf("subject-cfg-c", "subject-cfg-d")).owner;
      expect((await flagsFor(newcomer)).map(({ key }) => key)).not.toContain("split");
      const withVersion = await call("/v1/flags", {
        method: "GET",
        headers: { ...bearer(newcomer), [clientHeaders.appVersion]: "2.1.0+30" },
      });
      const listed = Schema.decodeUnknownSync(FlagsResponse)(await withVersion.json()).flags;
      expect(listed.map(({ key }) => key)).toContain("split");
    });

    it("lists no experiments for someone without a partner", async () => {
      expect(await flagsFor(await signedInAs("subject-alone"))).toEqual([]);
      expect(await storedFlags()).toEqual([]);
    });

    it("gives a pair its variants when it pairs, before anyone asks", async () => {
      const { pairId } = await pairOf("subject-owner", "subject-claimer");
      const stored = await storedFlags();
      expect(stored.map(({ pair_id }) => pair_id)).toEqual([pairId, pairId, pairId]);
      expect(stored.map(({ experiment_key }) => experiment_key).toSorted()).toEqual([
        "payments",
        "skewed",
        "split",
      ]);
    });

    it("gives both partners the same variants, and the same on every read", async () => {
      const { owner, claimer } = await pairOf("subject-owner", "subject-claimer");
      const [forOwner, forClaimer, again] = await Promise.all([
        flagsFor(owner),
        flagsFor(claimer),
        flagsFor(owner),
      ]);
      expect(forOwner.map(({ key }) => key)).toEqual(["split", "skewed", "payments"]);
      expect(forClaimer).toEqual(forOwner);
      expect(again).toEqual(forOwner);
      expect(await storedFlags()).toHaveLength(3);
    });

    it("never lists an experiment that is switched off, and stores nothing for it", async () => {
      const { owner } = await pairOf("subject-owner", "subject-claimer");
      expect((await flagsFor(owner)).map(({ key }) => key)).not.toContain("switched-off");
      expect((await storedFlags()).map(({ experiment_key }) => experiment_key)).not.toContain(
        "switched-off",
      );
    });

    it("only ever delivers a variant the experiment lists", async () => {
      const { owner } = await pairOf("subject-owner", "subject-claimer");
      const byKey = Object.fromEntries(
        (await flagsFor(owner)).map(({ key, variant }) => [key, variant]),
      );
      expect(["control", "bold"]).toContain(byKey["split"]);
      expect(["control", "loud", "quiet"]).toContain(byKey["skewed"]);
    });

    it("answers an unpaired partner with no experiments after unpairing, and keeps the pair's rows", async () => {
      const { owner, pairId } = await pairOf("subject-owner", "subject-claimer");
      expect((await call("/v1/pair", { method: "DELETE", headers: bearer(owner) })).status).toBe(
        204,
      );
      expect(await flagsFor(owner)).toEqual([]);
      expect((await storedFlags()).every((row) => row.pair_id === pairId)).toBe(true);
    });

    it("stores no personal data with an assignment", async () => {
      const { owner } = await pairOf("subject-owner", "subject-claimer");
      await flagsFor(owner);
      const stored = JSON.stringify(
        (await env.DB.prepare("SELECT * FROM pair_flags").all()).results,
      );
      expect(stored).not.toContain("subject-");
      expect(stored).not.toContain(owner);
    });
  });
});

describe("metrics", () => {
  const events = async () =>
    (
      await env.DB.prepare(
        "SELECT pair_id, user_id, name, day, count, first_at, last_at FROM pair_events ORDER BY name, user_id",
      ).all<{ pair_id: string; user_id: string; name: string; day: string; count: number }>()
    ).results;

  const report = (token: string, body: unknown) => call("/v1/events", json(body, "POST", token));

  const send = async (token: string) => {
    const response = await sendPhoto(token, await uploaded(token));
    expect(response.status).toBe(200);
  };

  it("needs a signed-in caller", async () => {
    expect((await call("/v1/events", json({ events: ["AppOpened"] }))).status).toBe(401);
    expect(await events()).toEqual([]);
  });

  it("counts the funnel as it happens: invite, pairing for both, a note each", async () => {
    const owner = await signedInAs("subject-owner");
    const claimer = await signedInAs("subject-claimer");
    await claimWith(claimer, await inviteFrom(owner));
    await send(owner);
    await send(claimer);
    await send(owner);
    const rows = await events();
    const count = (name: string) => rows.filter((row) => row.name === name).map((row) => row.count);
    expect(count("InviteCreated")).toEqual([1]);
    expect(count("PairClaimed")).toEqual([1, 1]);
    expect(count("NoteSent").toSorted()).toEqual([1, 2]);
    const pairIds = new Set(
      rows.filter((row) => row.name !== "InviteCreated").map((row) => row.pair_id),
    );
    expect(pairIds.size).toBe(1);
    expect(rows.find((row) => row.name === "InviteCreated")?.pair_id).toBe("");
  });

  it("counts a retried note once", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const image = await uploaded(owner);
    const key = crypto.randomUUID();
    await sendPhoto(owner, image, key);
    await sendPhoto(owner, image, key);
    expect((await events()).filter((row) => row.name === "NoteSent")).toMatchObject([{ count: 1 }]);
  });

  it("takes the events the app reports, under the caller's pair", async () => {
    const { owner, pairId } = await pairOf("subject-owner", "subject-claimer");
    expect(
      (await report(owner, { events: ["AppOpened", "WidgetAdded", "OpeningWatched"] })).status,
    ).toBe(204);
    expect((await report(owner, { events: ["AppOpened"] })).status).toBe(204);
    const rows = (await events()).filter((row) =>
      ["AppOpened", "WidgetAdded", "OpeningWatched"].includes(row.name),
    );
    expect(rows.map((row) => [row.name, row.count, row.pair_id])).toEqual([
      ["AppOpened", 2, pairId],
      ["OpeningWatched", 1, pairId],
      ["WidgetAdded", 1, pairId],
    ]);
  });

  it("refuses a name only the server may record, and keeps the table as it was", async () => {
    const owner = await signedInAs("subject-owner");
    const before = await events();
    expect((await report(owner, { events: ["NoteSent"] })).status).toBe(400);
    expect(await events()).toEqual(before);
  });

  it("stores no content: no image key, no stroke, no token, and only the fixed columns", async () => {
    const { owner } = await pairOf("subject-owner", "subject-claimer");
    const image = await uploaded(owner);
    await call(
      "/v1/notes",
      json(
        {
          _tag: "Drawing",
          key: crypto.randomUUID(),
          image,
          compact: {
            version: 1,
            strokes: [{ color: "#2A1A1C", width: 3, points: [4242, 4243, 4244, 4245] }],
          },
        },
        "POST",
        owner,
      ),
    );
    await report(owner, { events: ["AppOpened"], text: "a private message" });
    const dump = JSON.stringify((await env.DB.prepare("SELECT * FROM pair_events").all()).results);
    for (const secret of [image, "4242", "2A1A1C", owner, "private message", "subject-"]) {
      expect(dump).not.toContain(secret);
    }
    const columns = (await env.DB.prepare("PRAGMA table_info(pair_events)").all<{ name: string }>())
      .results;
    // The build and system are the app's own headers, in the shapes `clientInfoOf` allows.
    expect(columns.map(({ name }) => name).toSorted()).toEqual([
      "app_version",
      "count",
      "day",
      "first_at",
      "last_at",
      "name",
      "os",
      "pair_id",
      "user_id",
    ]);
  });

  it("does not fail a pairing or a note when it cannot count", async () => {
    await env.DB.prepare("ALTER TABLE pair_events RENAME TO pair_events_away").run();
    try {
      const { owner } = await pairOf("subject-owner", "subject-claimer");
      await send(owner);
    } finally {
      await env.DB.prepare("ALTER TABLE pair_events_away RENAME TO pair_events").run();
    }
  });
});

describe("payments in the Worker", () => {
  const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
    new Request(`https://billet.test${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", ...headers },
      body: JSON.stringify(body),
    });
  const purchasesAt = async (stage: string, headers: Record<string, string>) => {
    const response = await atStage(
      stage,
      new Request("https://billet.test/v1/purchases", { headers }),
    );
    expect(response.status).toBe(200);
    return Schema.decodeUnknownSync(PurchasesResponse)(await response.json());
  };
  const mockBody = (kind: "purchase" | "refund", transactionId: string) => ({
    productId: "com.mikitahimpel.billet.coins.550",
    transactionId,
    kind,
  });

  it.each([["prod"], ["stage"], [undefined]])("has no mock purchase route on %s", async (stage) => {
    const { owner } = await pairOf("subject-mock-a", "subject-mock-b");
    const response = await atStage(
      stage,
      post("/v1/purchases/mock", mockBody("purchase", "mock-1"), bearer(owner)),
    );
    expect(response.status).toBe(404);
    expect(await env.DB.prepare("SELECT * FROM coin_ledger").all()).toMatchObject({
      results: [],
    });
  });

  const walletOf = async (headers: Record<string, string>) => {
    const response = await atStage("dev", new Request("https://billet.test/v1/coins", { headers }));
    expect(response.status).toBe(200);
    return Schema.decodeUnknownSync(CoinsResponse)(await response.json());
  };

  it("credits and refunds mock purchases on dev, shared by the pair", async () => {
    const { owner, claimer, pairId } = await pairOf("subject-mock-a", "subject-mock-b");
    const transactionId = `mock-${crypto.randomUUID()}`;
    const bought = await atStage(
      "dev",
      post("/v1/purchases/mock", mockBody("purchase", transactionId), bearer(owner)),
    );
    expect(bought.status).toBe(200);
    // The wallet's balance: the welcome coins (560) and the pack.
    expect(Schema.decodeUnknownSync(PurchaseResponse)(await bought.json())).toEqual({
      transactionId,
      productId: "com.mikitahimpel.billet.coins.550",
      coins: 550,
      balance: 1110,
      duplicate: false,
    });
    expect((await purchasesAt("dev", bearer(claimer))).balance).toBe(550);
    const wallet = await walletOf(bearer(claimer));
    expect(wallet.balance).toBe(1110);
    expect(wallet.entries.at(-1)).toMatchObject({
      id: `purchase:${transactionId}`,
      kind: "buy",
      amount: 550,
    });

    const again = await atStage(
      "dev",
      post("/v1/purchases/mock", mockBody("purchase", transactionId), bearer(claimer)),
    );
    expect(Schema.decodeUnknownSync(PurchaseResponse)(await again.json())).toMatchObject({
      duplicate: true,
      balance: 1110,
    });

    const refunded = await atStage(
      "dev",
      post("/v1/purchases/mock", mockBody("refund", transactionId), bearer(claimer)),
    );
    expect(Schema.decodeUnknownSync(PurchaseResponse)(await refunded.json())).toMatchObject({
      coins: 550,
      balance: 560,
    });
    expect((await walletOf(bearer(owner))).entries.slice(-2)).toMatchObject([
      { id: `purchase:${transactionId}`, amount: 550 },
      { id: `refund:${transactionId}`, kind: "refund", amount: -550 },
    ]);
    const { entries } = await purchasesAt("dev", bearer(owner));
    expect(entries.map(({ id, amount }) => [id, amount])).toEqual([
      [`purchase:${transactionId}`, 550],
      [`refund:${transactionId}`, -550],
    ]);
    const rows = await env.DB.prepare("SELECT owner_id, environment, status FROM purchases").all();
    expect(rows.results).toEqual([{ owner_id: pairId, environment: "Mock", status: "refunded" }]);
  });

  const flagOff = async () => {
    const { owner, pairId } = await pairOf("subject-flag-a", "subject-flag-b");
    await env.DB.prepare(
      "INSERT INTO pair_flag_overrides (pair_id, experiment_key, variant, set_at, set_by) VALUES (?, 'payments', 'off', 0, 'test')",
    )
      .bind(pairId)
      .run();
    return owner;
  };

  it.each([["prod"], ["stage"]])(
    "answers 404 on %s on every purchase route to a pair the payments flag is off for",
    async (stage) => {
      const owner = await flagOff();
      const responses = [
        await atStage(stage, post("/v1/purchases", { signedTransaction: "a.b.c" }, bearer(owner))),
        await atStage(
          stage,
          new Request("https://billet.test/v1/purchases", { headers: bearer(owner) }),
        ),
      ];
      expect(responses.map(({ status }) => status)).toEqual([404, 404]);
      expect(await env.DB.prepare("SELECT * FROM coin_ledger").all()).toMatchObject({
        results: [],
      });
    },
  );

  it("sells on dev whatever the payments flag says", async () => {
    const owner = await flagOff();
    const bought = await atStage(
      "dev",
      post("/v1/purchases/mock", mockBody("purchase", "mock-off"), bearer(owner)),
    );
    expect(bought.status).toBe(200);
    const unsigned = await atStage(
      "dev",
      post("/v1/purchases", { signedTransaction: "a.b.c" }, bearer(owner)),
    );
    expect(unsigned.status).toBe(400);
    expect((await purchasesAt("dev", bearer(owner))).balance).toBe(550);
  });

  it("serves a demo room with no session on dev, and refuses it elsewhere", async () => {
    const demo = { "x-billet-demo-room": "AB2345CDEF" };
    const transactionId = `mock-${crypto.randomUUID()}`;
    const response = await atStage(
      "dev",
      post("/v1/purchases/mock", mockBody("purchase", transactionId), demo),
    );
    expect(response.status).toBe(200);
    expect((await purchasesAt("dev", demo)).balance).toBe(550);
    const rows = await env.DB.prepare("SELECT owner_id FROM coin_ledger").all();
    expect(rows.results).toEqual([{ owner_id: "demo:AB2345CDEF" }]);

    for (const stage of ["prod", undefined]) {
      const coins = await atStage(
        stage,
        new Request("https://billet.test/v1/purchases", { headers: demo }),
      );
      expect(coins.status).toBe(401);
      const purchase = await atStage(
        stage,
        post("/v1/purchases", { signedTransaction: "a.b.c" }, demo),
      );
      expect(purchase.status).toBe(401);
    }
  });

  it("credits an Xcode StoreKit transaction on dev only, once", async () => {
    const { owner } = await pairOf("subject-xcode-a", "subject-xcode-b");
    const xcode = await makeXcodeChain();
    const signedTransaction = await signJws(
      transactionPayload({ environment: "Xcode", transactionId: "7", originalTransactionId: "7" }),
      xcode.chain,
      xcode.leafKey,
    );
    const buy = (stage: string) =>
      atStage(stage, post("/v1/purchases", { signedTransaction }, bearer(owner)));

    const refused = await buy("prod");
    expect(refused.status).toBe(400);
    expect(await refused.json()).toEqual({ _tag: "InvalidPurchase" });

    const first = Schema.decodeUnknownSync(PurchaseResponse)(await (await buy("dev")).json());
    // The pair's wallet: the welcome coins (560) and the pack.
    expect(first).toMatchObject({
      transactionId: "7",
      coins: 100,
      balance: 660,
      duplicate: false,
    });
    const again = Schema.decodeUnknownSync(PurchaseResponse)(await (await buy("dev")).json());
    expect(again).toMatchObject({ balance: 660, duplicate: true });
  });

  it("trusts only Apple's root, for transactions and notifications", async () => {
    const { owner } = await pairOf("subject-root-a", "subject-root-b");
    const chain = await makeChain();
    const signedTransaction = await signJws(transactionPayload(), chain.chain, chain.leafKey);
    const purchase = await atStage(
      "prod",
      post("/v1/purchases", { signedTransaction }, bearer(owner)),
    );
    expect(purchase.status).toBe(400);
    const signedPayload = await signJws(
      notificationPayload("REFUND", signedTransaction),
      chain.chain,
      chain.leafKey,
    );
    // No session: Apple calls it.
    const notified = await atStage("prod", post("/v1/appstore/notifications", { signedPayload }));
    expect(notified.status).toBe(400);
    expect(await notified.json()).toEqual({ _tag: "InvalidPurchase" });
  });

  it("never logs a signed transaction or payload, and logs storage trouble once", async () => {
    const { owner } = await pairOf("subject-logs-a", "subject-logs-b");
    const xcode = await makeXcodeChain();
    const chain = await makeChain();
    const fromXcode = await signJws(
      transactionPayload({ environment: "Xcode", transactionId: "9", originalTransactionId: "9" }),
      xcode.chain,
      xcode.leafKey,
    );
    const foreign = await signJws(transactionPayload(), chain.chain, chain.leafKey);
    const signedPayload = await signJws(
      notificationPayload("REFUND", foreign),
      chain.chain,
      chain.leafKey,
    );
    const lines: string[] = [];
    const spies = (["log", "info", "warn", "error", "debug"] as const).map((level) =>
      vi.spyOn(console, level).mockImplementation((...args: unknown[]) => {
        lines.push(
          args.map((arg) => (typeof arg === "string" ? arg : JSON.stringify(arg))).join(" "),
        );
      }),
    );
    await env.DB.prepare("ALTER TABLE coin_ledger RENAME TO coin_ledger_away").run();
    try {
      const down = await atStage(
        "dev",
        post("/v1/purchases", { signedTransaction: fromXcode }, bearer(owner)),
      );
      expect(down.status).toBe(503);
    } finally {
      await env.DB.prepare("ALTER TABLE coin_ledger_away RENAME TO coin_ledger").run();
    }
    try {
      await atStage("dev", post("/v1/purchases", { signedTransaction: fromXcode }, bearer(owner)));
      await atStage("prod", post("/v1/purchases", { signedTransaction: foreign }, bearer(owner)));
      await atStage("prod", post("/v1/appstore/notifications", { signedPayload }));
    } finally {
      for (const spy of spies) spy.mockRestore();
    }
    const output = lines.join("\n");
    expect(output.match(/payments unavailable/g)).toHaveLength(1);
    expect(output).toContain("directory-unavailable");
    for (const jws of [fromXcode, foreign, signedPayload]) {
      for (const part of jws.split(".")) expect(output).not.toContain(part);
    }
    expect(output).not.toContain(owner);
  });

  it("answers 404 to a purchase from a caller with no pair", async () => {
    const token = await signedInAs("subject-alone");
    const response = await atStage(
      "dev",
      new Request("https://billet.test/v1/purchases", { headers: bearer(token) }),
    );
    expect(response.status).toBe(404);
  });
});
