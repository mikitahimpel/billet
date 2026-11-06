import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { GuessResponse } from "@billet/contracts-http-api/guess";
import { routes } from "@billet/contracts-http-api/routes";
import { GuessRoutes } from "../src/guess-routes.ts";
import { GuessService } from "../src/guess-service.ts";
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
  GuessRoutes.pipe(
    Layer.provide(Layer.mergeAll(FakeAuth, GuessService.layer)),
    Layer.provide(world.layer),
  ),
  { disableLogger: true },
);

afterAll(dispose);

const decode = Schema.decodeUnknownSync(GuessResponse);

const call = async (name: string, body?: unknown) => {
  const route = body === undefined ? routes.getGuess : routes.answerGuess;
  const response = await handler(
    new Request(`http://billet.test${route.path}`, {
      method: route.method,
      headers: { authorization: `Bearer ${tokenOf(name)}` },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }),
  );
  return {
    status: response.status,
    cache: response.headers.get("cache-control"),
    view: response.status === 200 ? decode(await response.json()) : undefined,
  };
};

// The cases run in order on one world.
describe("the Who knows who routes", () => {
  let round = "";
  let questions: ReadonlyArray<number> = [];

  it("open the room on the first call with today's round, kept out of caches", async () => {
    const first = await call("ana");
    expect(first).toMatchObject({ status: 200, cache: "no-store" });
    round = first.view!.round.id;
    questions = first.view!.round.questions;
    expect(questions).toHaveLength(5);
    expect(["ana", "ben"]).toContain(first.view!.round.subject);
    expect((await call("ben")).view?.round).toEqual(first.view!.round);
  });

  it("lock each answer and show the partner only a count", async () => {
    for (const question of questions) {
      expect((await call("ana", { round, question, option: 1 })).status).toBe(200);
    }
    const [question] = questions;
    expect((await call("ana", { round, question, option: 1 })).status).toBe(200);
    expect((await call("ana", { round, question, option: 2 })).status).toBe(409);
    const ben = (await call("ben")).view!;
    expect(ben).toMatchObject({ answers: [], partnerAnswered: 5 });
    expect(ben.reveal).toBeUndefined();
  });

  it("refuse a question outside the round, another day's round, a stranger and a bad body", async () => {
    const outside = [1, 2, 3, 4, 5, 6, 7].find((id) => !questions.includes(id));
    expect((await call("ben", { round, question: outside, option: 0 })).status).toBe(400);
    expect(
      (await call("ben", { round: "2020-01-01", question: questions[0], option: 0 })).status,
    ).toBe(409);
    expect((await call("stranger")).status).toBe(404);
    expect((await call("ben", { round, question: questions[0], option: 4 })).status).toBe(400);
  });

  it("reveal the round to both once the partner answered everything", async () => {
    let last;
    for (const question of questions) last = await call("ben", { round, question, option: 1 });
    expect(last?.view?.reveal).toHaveLength(5);
    expect(last?.view?.reveal?.every((question) => question.hit)).toBe(true);
    const ana = (await call("ana")).view!;
    expect(ana.reveal).toEqual(last?.view?.reveal);
    const guesser = ana.round.subject === "ana" ? "partner" : "mine";
    expect(ana.score.week[guesser]).toBe(5);
  });
});
