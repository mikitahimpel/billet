import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import { MoodCheckIn, moodNoteMaxLength } from "@billet/contracts-domain/mood";
import { MoodRoutes } from "../src/mood-routes.ts";
import { MoodService } from "../src/mood-service.ts";
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
  MoodRoutes.pipe(
    Layer.provide(Layer.mergeAll(FakeAuth, MoodService.layer)),
    Layer.provide(world.layer),
  ),
  { disableLogger: true },
);

afterAll(dispose);

const setMood = (name: string, body: unknown) =>
  handler(
    new Request("http://billet.test/v1/mood", {
      method: "PUT",
      headers: { authorization: `Bearer ${tokenOf(name)}` },
      body: JSON.stringify(body),
    }),
  );

const decodeCheckIn = Schema.decodeUnknownSync(MoodCheckIn);

// The cases run in order on one world.
describe("the mood route", () => {
  it("opens the room on the first check-in and answers with what it stored, trimmed", async () => {
    const response = await setMood("ben", { mood: "busy", note: "  deadline till 6 " });
    expect(response.status).toBe(200);
    expect(decodeCheckIn(await response.json())).toEqual({
      user: "ben",
      mood: "busy",
      note: "deadline till 6",
      at: expect.any(Number),
    });
  });

  it("replaces the caller's check-in, keeps the partner's, and tells the partner's Inbox", async () => {
    await setMood("ana", { mood: "missing" });
    const replaced = decodeCheckIn(await (await setMood("ben", { mood: "sleepy" })).json());
    expect(replaced).not.toHaveProperty("note");
    const moods = await Effect.runPromise(world.pairRooms.moods(pair("pair-a")));
    expect(moods.map(({ user: who, mood }) => [who, mood])).toEqual([
      ["ana", "missing"],
      ["ben", "sleepy"],
    ]);
    const inbox = await Effect.runPromise(
      world.pairRooms.activity(pair("pair-a"), user("ana"), undefined, 10),
    );
    expect(inbox.items.map(({ actor, event }) => [actor, event])).toEqual([
      ["Partner", { _tag: "MoodShared", mood: "sleepy" }],
      ["Me", { _tag: "MoodShared", mood: "missing" }],
    ]);
    expect(inbox.unread).toBe(1);
  });

  it("refuses a note too long, a mood it does not know, and a caller with no partner", async () => {
    const long = await setMood("ana", { mood: "happy", note: "a".repeat(moodNoteMaxLength + 1) });
    expect(long.status).toBe(400);
    expect(await long.json()).toEqual({ _tag: "InvalidRequest" });
    expect((await setMood("ana", { mood: "grumpy" })).status).toBe(400);
    expect((await setMood("cal", { mood: "happy" })).status).toBe(404);
  });
});
