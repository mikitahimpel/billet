import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { Riddle } from "@billet/contracts-domain/riddle";
import { GuessRiddleResponse, RiddlesResponse } from "@billet/contracts-http-api/riddle";
import { riddlePath, routes, type Route } from "@billet/contracts-http-api/routes";
import { RiddleRoutes } from "../src/riddle-routes.ts";
import { RiddleService } from "../src/riddle-service.ts";
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
  RiddleRoutes.pipe(
    Layer.provide(Layer.mergeAll(FakeAuth, RiddleService.layer)),
    Layer.provide(world.layer),
  ),
  { disableLogger: true },
);

afterAll(dispose);

const call = async (name: string, route: Route, path: string, body?: unknown) => {
  const response = await handler(
    new Request(`http://billet.test${path}`, {
      method: route.method,
      headers: { authorization: `Bearer ${tokenOf(name)}` },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }),
  );
  return {
    status: response.status,
    cache: response.headers.get("cache-control"),
    json: response.status === 200 ? ((await response.json()) as unknown) : undefined,
  };
};

const id = "00000000-0000-4000-8000-000000000001";
const key = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const sendBody = {
  id,
  word: " Cat ",
  compact: { version: 1, strokes: [] },
  image: "pairs/a/r.png",
};
const list = (name: string) => call(name, routes.getRiddles, routes.getRiddles.path);
const guess = (name: string, n: number, text: string) =>
  call(name, routes.guessRiddle, riddlePath(routes.guessRiddle, id), { key: key(n), guess: text });

// The cases run in order on one world.
describe("the draw-guess routes", () => {
  it("send a riddle, kept out of caches, and show its word to the drawer only", async () => {
    const sent = await call("ana", routes.sendRiddle, routes.sendRiddle.path, sendBody);
    expect(sent).toMatchObject({ status: 200, cache: "no-store" });
    expect(Schema.decodeUnknownSync(Riddle)(sent.json)).toMatchObject({ word: "cat", shape: [3] });
    const ben = Schema.decodeUnknownSync(RiddlesResponse)((await list("ben")).json);
    expect(ben.open).toHaveLength(1);
    expect(ben.open[0]?.word).toBeUndefined();
    expect((await call("ana", routes.sendRiddle, routes.sendRiddle.path, sendBody)).status).toBe(
      200,
    );
  });

  it("refuse a bad word, a second open riddle, the drawer's try and a riddle not held", async () => {
    const other = { ...sendBody, id: key(2) };
    expect(
      (await call("ana", routes.sendRiddle, routes.sendRiddle.path, { ...other, word: "c4t" }))
        .status,
    ).toBe(400);
    expect((await call("ana", routes.sendRiddle, routes.sendRiddle.path, other)).status).toBe(409);
    expect((await guess("ana", 1, "cat")).status).toBe(409);
    const missing = riddlePath(routes.hintRiddle, key(3));
    expect((await call("ben", routes.hintRiddle, missing)).status).toBe(404);
    expect(
      (await call("ben", routes.hintRiddle, riddlePath(routes.hintRiddle, "nope"))).status,
    ).toBe(400);
    expect((await list("stranger")).status).toBe(404);
  });

  it("take tries and hints, and end the round on the word", async () => {
    const hint = await call("ben", routes.hintRiddle, riddlePath(routes.hintRiddle, id));
    expect(Schema.decodeUnknownSync(Riddle)(hint.json).removed.length).toBeGreaterThan(0);
    const wrong = Schema.decodeUnknownSync(GuessRiddleResponse)(
      (await guess("ben", 1, "dog")).json,
    );
    expect(wrong).toMatchObject({ right: false, riddle: { tries: 1 } });
    expect(wrong.riddle.word).toBeUndefined();
    const right = Schema.decodeUnknownSync(GuessRiddleResponse)(
      (await guess("ben", 2, "CAT")).json,
    );
    expect(right).toMatchObject({ right: true, riddle: { word: "cat", tries: 2 } });
    expect((await guess("ben", 2, "x")).json).toEqual((await guess("ben", 2, "y")).json);
    const giveUp = riddlePath(routes.giveUpRiddle, id);
    expect((await call("ben", routes.giveUpRiddle, giveUp)).status).toBe(409);
    const after = Schema.decodeUnknownSync(RiddlesResponse)((await list("ana")).json);
    expect(after).toMatchObject({ open: [], series: 1, best: 1, ended: [{ word: "cat" }] });
  });
});
