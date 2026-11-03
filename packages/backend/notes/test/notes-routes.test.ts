import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthRejected } from "@billet/backend-auth/auth-error";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { UploadImageResponse } from "@billet/contracts-http-api/note";
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

const world = makeWorld([[pair("pair-a"), user("ana"), user("ben")]]);

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

  it("answers 400 to bytes that aren't a PNG", async () => {
    expect((await upload("ana", "hello")).status).toBe(400);
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
