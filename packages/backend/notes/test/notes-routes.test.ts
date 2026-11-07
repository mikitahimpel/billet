import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthRejected } from "@billet/backend-auth/auth-error";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import {
  noteTextMaxCharacters,
  noteTextMaxUnits,
  photoPreviewMaxLength,
} from "@billet/contracts-domain/note";
import { SendNoteResponse, UploadImageResponse } from "@billet/contracts-http-api/note";
import { NotesUnavailable } from "../src/notes-error.ts";
import { imageSizeLimit, NotesRoutes } from "../src/notes-routes.ts";
import { NotesService } from "../src/notes-service.ts";
import { PairRooms } from "../src/pair-rooms.ts";
import { makeWorld, pair, user } from "./fake-world.ts";

const tokenOf = (name: string) => name.padEnd(43, "x");

const FakeAuth = Layer.succeed(
  AuthService,
  AuthService.of({
    issueChallenge: Effect.die("unused"),
    signInAnonymously: () => Effect.die("unused"),
    signInWithApple: () => Effect.die("unused"),
    linkApple: () => Effect.die("unused"),
    account: () => Effect.die("unused"),
    signOut: () => Effect.die("unused"),
    registerPushToken: () => Effect.die("unused"),
    authenticate: (token) => {
      const raw = Redacted.value(token);
      if (raw.startsWith("rejected")) return Effect.fail(new AuthRejected({ reason: "fake" }));
      const principal: Principal = {
        userId: user(raw.replace(/x+$/, "")),
        deviceId: Schema.decodeSync(DeviceId)("device"),
        sessionHash: "hash",
      };
      return Effect.succeed(principal);
    },
  }),
);

const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0xff]);

const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08]);
const heic = Uint8Array.from([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]);

const world = makeWorld([
  [pair("pair-a"), user("ana"), user("ben")],
  [pair("pair-b"), user("cal"), user("dee")],
]);

const setup = (dependencies: typeof world.layer) =>
  HttpRouter.toWebHandler(
    NotesRoutes.pipe(
      Layer.provide(Layer.merge(FakeAuth, NotesService.layer)),
      Layer.provide(dependencies),
    ),
    { disableLogger: true },
  );

const { handler, dispose } = setup(world.layer);

afterAll(dispose);

const request = (path: string, name: string, init: RequestInit = {}) =>
  new Request(`http://billet.test${path}`, {
    method: "GET",
    ...init,
    headers: { authorization: `Bearer ${tokenOf(name)}`, ...init.headers },
  });

const upload = (name: string, body: BodyInit = png) =>
  handler(request("/v1/media", name, { method: "POST", body }));

const uploadedKey = async (name: string, body: BodyInit) =>
  Schema.decodeUnknownSync(UploadImageResponse)(await (await upload(name, body)).json()).image;

describe("the media routes", () => {
  it("serves an uploaded PNG, byte for byte, as an image nobody may cache", async () => {
    const uploaded = await upload("ana");
    expect(uploaded.status).toBe(200);
    const { image } = Schema.decodeUnknownSync(UploadImageResponse)(await uploaded.json());

    const read = await handler(request(`/v1/media/${image}`, "ben"));

    expect(read.status).toBe(200);
    expect(read.headers.get("content-type")).toBe("image/png");
    expect(read.headers.get("cache-control")).toBe("no-store");
    expect(read.headers.get("x-content-type-options")).toBe("nosniff");
    expect(new Uint8Array(await read.arrayBuffer())).toEqual(png);
  });

  it("answers 400 to a body over the limit, without storing it", async () => {
    const before = world.objects.size;
    const oversized = new Uint8Array(Number(imageSizeLimit) + 1);
    oversized.set(png);
    const response = await upload("ana", oversized);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ _tag: "InvalidRequest" });
    expect(world.objects.size).toBe(before);
  });

  it.each([
    ["a JPEG", jpeg, ".jpg", "image/jpeg"],
    ["a HEIC", heic, ".heic", "image/heic"],
  ])("serves %s under its own extension and content type", async (_, bytes, extension, type) => {
    const image = await uploadedKey("ana", bytes);
    expect(image.endsWith(extension)).toBe(true);

    const read = await handler(request(`/v1/media/${image}`, "ben"));

    expect(read.status).toBe(200);
    expect(read.headers.get("content-type")).toBe(type);
    expect(read.headers.get("cache-control")).toBe("no-store");
    expect(new Uint8Array(await read.arrayBuffer())).toEqual(bytes);
  });

  it("answers 400 to a JPEG over the limit, without storing it", async () => {
    const before = world.objects.size;
    const oversized = new Uint8Array(Number(imageSizeLimit) + 1);
    oversized.set(jpeg);
    expect((await upload("ana", oversized)).status).toBe(400);
    expect(world.objects.size).toBe(before);
  });

  it("answers 400 to bytes that aren't a PNG, JPEG or HEIC", async () => {
    const before = world.objects.size;
    expect((await upload("ana", "hello")).status).toBe(400);
    expect(
      (await upload("ana", Uint8Array.from([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]))).status,
    ).toBe(400);
    expect(world.objects.size).toBe(before);
  });

  it("answers another couple the 404 of a missing image for a photo", async () => {
    const image = await uploadedKey("ana", jpeg);
    const theirs = await handler(request(`/v1/media/${image}`, "cal"));
    const missing = await handler(request("/v1/media/pairs/pair-a/notes/none.jpg", "ana"));
    expect([theirs.status, missing.status]).toEqual([404, 404]);
    expect(await theirs.json()).toEqual(await missing.json());
  });

  it("answers 401 to a rejected session", async () => {
    expect((await upload("rejected")).status).toBe(401);
    expect((await handler(request("/v1/notes", "rejected"))).status).toBe(401);
  });

  it("answers the same 404 to a stranger and for a missing image", async () => {
    const missing = await handler(request("/v1/media/pairs/pair-a/notes/none.png", "ana"));
    const stranger = await handler(request("/v1/media/pairs/pair-a/notes/none.png", "eve"));
    expect([missing.status, stranger.status]).toEqual([404, 404]);
    expect(await stranger.json()).toEqual(await missing.json());
  });
});

describe("the notes routes", () => {
  it("answers 400 to a body that isn't a note, or is far too large to be one", async () => {
    const post = (body: string) => handler(request("/v1/notes", "ana", { method: "POST", body }));
    expect((await post(JSON.stringify({ _tag: "Letter" }))).status).toBe(400);
    expect((await post("x".repeat(17 * 1024))).status).toBe(400);
  });

  const postNote = (name: string, body: unknown) =>
    handler(request("/v1/notes", name, { method: "POST", body: JSON.stringify(body) }));

  it("takes the largest photo note there can be, under the note size limit", async () => {
    const image = await uploadedKey("ana", jpeg);
    // 120 characters, each a letter under three-byte combining marks, to the UTF-16 cap: the most
    // bytes a caption can take. And a 9 by 9 BlurHash, the longest preview.
    const character = `a${"\u20d0".repeat(Math.floor(noteTextMaxUnits / noteTextMaxCharacters) - 1)}`;
    const longest = {
      caption: character.repeat(noteTextMaxCharacters),
      preview: `|${"0".repeat(photoPreviewMaxLength - 1)}`,
    };
    const response = await postNote("ana", {
      _tag: "Photo",
      key: "00000000-0000-4000-8000-00000000f070",
      image,
      width: 8192,
      height: 8192,
      ...longest,
    });
    expect(response.status).toBe(200);
    const { note } = Schema.decodeUnknownSync(SendNoteResponse)(await response.json());
    expect(note).toMatchObject({ _tag: "Photo", image, width: 8192, ...longest });
  });

  it("answers 400 to a photo without its size or preview", async () => {
    const image = await uploadedKey("ana", jpeg);
    const key = "00000000-0000-4000-8000-00000000f071";
    expect((await postNote("ana", { _tag: "Photo", key, image })).status).toBe(400);
    expect(
      (await postNote("ana", { _tag: "Photo", key, image, width: 1, height: 1, preview: "x" }))
        .status,
    ).toBe(400);
  });

  it.each(["?limit=0", "?limit=101", "?limit=-1", "?after=-1", "?after=x"])(
    "answers 400 to %s",
    async (query) => {
      expect((await handler(request(`/v1/notes${query}`, "ana"))).status).toBe(400);
    },
  );

  it("answers 503, with a fixed label only, when the room can't be reached", async () => {
    const down = makeWorld([[pair("pair-a"), user("ana"), user("ben")]]);
    const { handler: failing, dispose: disposeFailing } = setup(
      Layer.merge(
        down.layer,
        Layer.succeed(PairRooms, {
          ...down.pairRooms,
          notesAfter: () => Effect.fail(new NotesUnavailable({ reason: "room-unavailable" })),
        }),
      ),
    );
    const response = await failing(request("/v1/notes", "ana"));
    await disposeFailing();
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ _tag: "Unavailable" });
  });
});

describe("the shop routes", () => {
  const json = (body: unknown): RequestInit => ({
    method: "PUT",
    body: JSON.stringify(body),
    headers: { "content-type": "application/json" },
  });

  it("answers a new pair the free ink and the starter pieces, never cached", async () => {
    const response = await handler(request("/v1/shop", "cal"));
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    // Reading the shop opens the room, so the welcome coins are there on the first read.
    expect(await response.json()).toEqual({
      balance: 560,
      inks: ["ink-graphite"],
      items: ["lamp", "rug"],
      wishlist: [],
      bonuses: [],
    });
  });

  it("keeps one wishlist for both partners", async () => {
    const wished = await handler(
      request("/v1/shop/wishlist", "ana", json({ item: "tower", wished: true })),
    );
    expect(wished.status).toBe(200);
    const seen = await (await handler(request("/v1/shop", "ben"))).json();
    expect(seen).toMatchObject({ wishlist: ["tower"] });
  });

  it("answers 409 to an order the balance cannot pay, and 404 to a piece the catalog does not sell", async () => {
    const order = (item: string, n: number) =>
      handler(
        request("/v1/shop/orders", "dee", {
          ...json({
            id: `00000000-0000-4000-8000-00000000000${n}`,
            offer: { _tag: "Item", item },
          }),
          method: "POST",
        }),
      );
    // The welcome coins pay for the tower and leave 20. Neither piece is ever a deal.
    expect((await order("tower", 1)).status).toBe(200);
    const poor = await order("armchair", 2);
    expect(poor.status).toBe(409);
    expect(await poor.json()).toEqual({ _tag: "NotEnoughCoins", needed: 320, have: 20 });
    expect((await order("throne", 3)).status).toBe(404);
  });

  it("answers a stranger 404", async () => {
    expect((await handler(request("/v1/shop", "eve"))).status).toBe(404);
  });
});
