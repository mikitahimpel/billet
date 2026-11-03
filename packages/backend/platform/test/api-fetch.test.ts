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
import { limits } from "../src/rate-limit.ts";
import { mediaPath, routes } from "@billet/contracts-http-api/routes";
import { imageSizeLimit } from "@billet/backend-notes/notes-routes";
import { AuthChallengeResponse, SessionResponse } from "@billet/contracts-http-api/auth";
import { FlagsResponse } from "@billet/contracts-http-api/flags";
import { ClaimInviteResponse, CreateInviteResponse } from "@billet/contracts-http-api/invite";
import {
  ListNotesResponse,
  SendNoteResponse,
  UploadImageResponse,
} from "@billet/contracts-http-api/note";
import { resetDirectory } from "./directory-migrations.ts";
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

const claims = (nonce: string, overrides: Record<string, unknown> = {}) =>
  new TextEncoder().encode(
    JSON.stringify({
      iss: appleIssuer,
      aud: appleAudience,
      sub: "subject-a",
      nonce,
      exp: Math.floor(Date.now() / 1000) + 300,
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
  "users",
  "devices",
  "sessions",
  "auth_challenges",
  "push_tokens",
  "invites",
  "pair_members",
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

const upload = (token: string, body: BodyInit = pngBytes) =>
  call("/v1/media", { body, headers: { ...bearer(token), "content-type": "image/png" } });

const uploaded = async (token: string) => {
  const response = await upload(token);
  expect(response.status).toBe(200);
  return Schema.decodeUnknownSync(UploadImageResponse)(await response.json()).image;
};

const readImage = (key: string, token: string) =>
  call(`/v1/media/${key}`, { method: "GET", headers: bearer(token) });

const sendPhoto = (token: string, image: string, key: string = crypto.randomUUID()) =>
  call("/v1/notes", json({ _tag: "Photo", key, image }, "POST", token));

const sentPhoto = async (token: string) => {
  const response = await sendPhoto(token, await uploaded(token));
  expect(response.status).toBe(200);
  return Schema.decodeUnknownSync(SendNoteResponse)(await response.json()).note;
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

    const rows = await env.DB.prepare("SELECT token_hash FROM sessions").all();
    expect(rows.results).toEqual([{ token_hash: await sha256Hex(session.sessionToken) }]);
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
    ["expired", { exp: Math.floor(Date.now() / 1000) - 300 }],
    ["wrong-audience", { aud: "com.example.other" }],
  ])("refuses an %s token and stores no session", async (_, overrides) => {
    const { response } = await signIn(overrides);
    expect(response.status).toBe(401);
    expect(await env.DB.prepare("SELECT * FROM sessions").first()).toBeNull();
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
    expect(await env.DB.prepare("SELECT * FROM sessions").first()).toBeNull();
  });

  it("serves concurrent sign-ins while no keys are loaded, each on its own fetch", async () => {
    const results = await Promise.all(Array.from({ length: 5 }, () => signIn()));
    expect(results.map(({ response }) => response.status)).toEqual([200, 200, 200, 200, 200]);
    expect(appleFetch).toHaveBeenCalledTimes(5);
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

  it("refuses bytes that aren't a PNG, and an image over the limit", async () => {
    const { owner, pairId } = await pairOf("subject-owner", "subject-claimer");

    expect((await upload(owner, "not an image")).status).toBe(400);

    const oversized = new Uint8Array(imageSizeInBytes + 1);
    oversized.set(pngSignature);
    expect((await upload(owner, oversized)).status).toBe(400);

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
  });
});

describe("routes from the contracts", () => {
  const send = (method: string, path: string) =>
    exports.default.fetch(new Request(`https://billet.test${path}`, { method }));
  const concrete = (path: string) => (path.endsWith("*") ? mediaPath("pairs/p/notes/n.png") : path);

  it.each(Object.entries(routes))("%s is served at its method and path", async (_, route) => {
    // Whatever the answer is, it is not "no such route".
    expect((await send(route.method, concrete(route.path))).status).not.toBe(404);
  });

  it.each(Object.entries(routes))("%s is is not served under another path", async (_, route) => {
    const moved = concrete(route.path).replace("/v1/", "/v1/moved/");
    expect((await send(route.method, moved)).status).toBe(404);
  });
});

describe("rate limits in the Worker", () => {
  const challengeFrom = () =>
    exports.default.fetch(
      new Request("https://billet.test/v1/auth/challenge", {
        method: "POST",
        headers: { "cf-connecting-ip": "203.0.113.50" },
      }),
    );

  it("answers 429 past the limit on a limited route, and not on others", async () => {
    for (let i = 0; i < limits.auth; i++) expect((await challengeFrom()).status).toBe(200);
    expect((await challengeFrom()).status).toBe(429);
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

    it("lists no experiments for someone without a partner", async () => {
      expect(await flagsFor(await signedInAs("subject-alone"))).toEqual([]);
      expect(await storedFlags()).toEqual([]);
    });

    it("gives a pair its variants when it pairs, before anyone asks", async () => {
      const { pairId } = await pairOf("subject-owner", "subject-claimer");
      const stored = await storedFlags();
      expect(stored.map(({ pair_id }) => pair_id)).toEqual([pairId, pairId]);
      expect(stored.map(({ experiment_key }) => experiment_key).toSorted()).toEqual([
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
      expect(forOwner.map(({ key }) => key)).toEqual(["split", "skewed"]);
      expect(forClaimer).toEqual(forOwner);
      expect(again).toEqual(forOwner);
      expect(await storedFlags()).toHaveLength(2);
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
    expect(columns.map(({ name }) => name).toSorted()).toEqual([
      "count",
      "day",
      "first_at",
      "last_at",
      "name",
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
