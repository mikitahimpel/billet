import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { ActivityResponse, ActivityUnreadResponse } from "@billet/contracts-http-api/activity";
import { ActivityRoutes } from "../src/activity-routes.ts";
import { ActivityService } from "../src/activity-service.ts";
import { CatRoutes } from "../src/cat-routes.ts";
import { CatService } from "../src/cat-service.ts";
import { NotesRoutes } from "../src/notes-routes.ts";
import { NotesService } from "../src/notes-service.ts";
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
    authenticate: (token) =>
      Effect.succeed({
        userId: user(Redacted.value(token).replace(/x+$/, "")),
        deviceId: Schema.decodeSync(DeviceId)("device"),
        sessionHash: "hash",
      } satisfies Principal),
  }),
);

const world = makeWorld([
  [pair("pair-a"), user("ana"), user("ben")],
  [pair("pair-b"), user("cleo"), user("dan")],
]);

const { handler, dispose } = HttpRouter.toWebHandler(
  Layer.mergeAll(ActivityRoutes, CatRoutes, NotesRoutes).pipe(
    Layer.provide(
      Layer.mergeAll(FakeAuth, ActivityService.layer, CatService.layer, NotesService.layer),
    ),
    Layer.provide(world.layer),
  ),
  { disableLogger: true },
);

afterAll(dispose);

const call = (method: string, path: string, name: string, body?: unknown) =>
  handler(
    new Request(`http://billet.test${path}`, {
      method,
      headers: { authorization: `Bearer ${tokenOf(name)}` },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }),
  );

const decodePage = Schema.decodeUnknownSync(ActivityResponse);
const decodeUnread = Schema.decodeUnknownSync(ActivityUnreadResponse);
const page = async (name: string, query = "") =>
  decodePage(await (await call("GET", `/v1/activity${query}`, name)).json());

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const mochi = { name: "Mochi", look: { model: "marmalade", coat: "natural" }, utcOffsetSeconds: 0 };

// The cases run in order on one world: each builds on the activity the one before left.
describe("the activity routes", () => {
  it("starts empty for a couple that has done nothing yet", async () => {
    expect(await page("ana")).toEqual({ items: [], unread: 0 });
  });

  it("lists the couple's cat care and notes, each from the caller's side", async () => {
    await call("PUT", "/v1/cat", "ana", mochi);
    await call("POST", "/v1/cat/events", "ben", { id: id(1), event: { _tag: "Fed", grams: 30 } });
    await call("POST", "/v1/notes", "ben", { _tag: "Text", key: id(2), text: "hi" });

    const ana = await page("ana");
    expect(ana.items.map((i) => [i.actor, i.event._tag]).toSorted()).toEqual([
      ["Me", "CatAdopted"],
      ["Partner", "CatFed"],
      ["Partner", "NoteSent"],
    ]);
    expect(ana.unread).toBe(2);
    expect((await page("ben")).unread).toBe(1);
    const note = ana.items.find((i) => i.event._tag === "NoteSent");
    expect(note?.target).toEqual({
      _tag: "Note",
      note: note?.event._tag === "NoteSent" ? note.event.note : "",
    });
  });

  it("pages with a cursor, and reading moves only the reader's count", async () => {
    const first = await page("ana", "?limit=2");
    expect(first.items).toHaveLength(2);
    expect(first.next).toBeDefined();
    const rest = await page("ana", `?limit=2&before=${encodeURIComponent(first.next ?? "")}`);
    expect(rest.items).toHaveLength(1);
    expect(rest.next).toBeUndefined();

    const newest = first.items[0];
    const upTo = `${String(newest?.at ?? 0).padStart(16, "0")}~${newest?.id ?? ""}`;
    const read = await call("POST", "/v1/activity/read", "ana", { upTo });
    expect(decodeUnread(await read.json())).toEqual({ unread: 0 });
    expect((await page("ben")).unread).toBe(1);
  });

  it("keeps each couple's activity to itself, and answers 404 to someone with no pair", async () => {
    expect((await page("cleo")).items).toEqual([]);
    expect((await call("GET", "/v1/activity", "eve")).status).toBe(404);
    expect(
      (await call("POST", "/v1/activity/read", "eve", { upTo: `${"0".repeat(16)}~cat:x` })).status,
    ).toBe(404);
  });

  it.each(["?limit=0", "?limit=51", "?before=yesterday"])("answers 400 to %s", async (query) => {
    expect((await call("GET", `/v1/activity${query}`, "ana")).status).toBe(400);
  });

  it("answers 400 to a read mark that is not a cursor", async () => {
    expect((await call("POST", "/v1/activity/read", "ana", { upTo: "latest" })).status).toBe(400);
  });
});
