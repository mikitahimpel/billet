import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId, IdempotencyKey, MediaKey } from "@billet/contracts-domain/ids";
import { SendNoteRequest } from "@billet/contracts-http-api/note";
import { ListReactionsResponse, ReactResponse } from "@billet/contracts-http-api/reaction";
import { ReactionRoutes } from "../src/reaction-routes.ts";
import { ReactionService } from "../src/reaction-service.ts";
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

const world = makeWorld([[pair("pair-a"), user("ana"), user("ben")]]);

const { handler, dispose } = HttpRouter.toWebHandler(
  ReactionRoutes.pipe(
    Layer.provide(Layer.mergeAll(FakeAuth, ReactionService.layer)),
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

const sendPhoto = Effect.gen(function* () {
  yield* world.pairRooms.open(pair("pair-a"), [user("ana"), user("ben")]);
  const decision = yield* world.pairRooms.sendNote(
    pair("pair-a"),
    user("ana"),
    SendNoteRequest.cases.Photo.make({
      key: Schema.decodeSync(IdempotencyKey)("00000000-0000-4000-8000-0000000000a1"),
      image: Schema.decodeSync(MediaKey)("pairs/pair-a/notes/a.jpg"),
      width: 4,
      height: 3,
      preview: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
    }),
  );
  if (decision._tag !== "Accepted") throw new Error("note refused");
  return decision.outputs.flatMap((o) => (o._tag === "NoteAppended" ? [o.entry.note.id] : []))[0]!;
});

// The cases run in order on one world.
describe("the reaction routes", () => {
  const note = Effect.runSync(sendPhoto);

  it("sets the partner's reaction, answers a repeat with the same one, and lists each change", async () => {
    const first = await call("PUT", "/v1/reactions", "ben", { note, reaction: "heart" });
    expect(first.status).toBe(200);
    const { reaction } = Schema.decodeUnknownSync(ReactResponse)(await first.json());
    expect(reaction).toMatchObject({ rev: 1, note, by: "ben", reaction: "heart" });

    const again = await call("PUT", "/v1/reactions", "ben", { note, reaction: "heart" });
    expect(Schema.decodeUnknownSync(ReactResponse)(await again.json()).reaction).toEqual(reaction);

    await call("PUT", "/v1/reactions", "ben", { note });
    const list = Schema.decodeUnknownSync(ListReactionsResponse)(
      await (await call("GET", "/v1/reactions?after=0", "ana")).json(),
    );
    expect(list.reactions).toEqual([expect.objectContaining({ rev: 2, by: "ben" })]);
    expect(list.reactions[0]?.reaction).toBeUndefined();
  });

  it("refuses a reaction to an own photo, to an unknown note, or that is not one", async () => {
    expect((await call("PUT", "/v1/reactions", "ana", { note, reaction: "fire" })).status).toBe(
      400,
    );
    expect(
      (await call("PUT", "/v1/reactions", "ben", { note: "nope", reaction: "fire" })).status,
    ).toBe(404);
    expect((await call("PUT", "/v1/reactions", "ben", { note, reaction: "meh" })).status).toBe(400);
  });
});
