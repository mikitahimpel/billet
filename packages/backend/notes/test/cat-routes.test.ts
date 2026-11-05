import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { DeviceId } from "@billet/contracts-domain/ids";
import {
  CatJournalResponse,
  CatResponse,
  RecordCatEventResponse,
} from "@billet/contracts-http-api/cat";
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
  Layer.mergeAll(CatRoutes, NotesRoutes).pipe(
    Layer.provide(Layer.mergeAll(FakeAuth, CatService.layer, NotesService.layer)),
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

const decodeCat = Schema.decodeUnknownSync(CatResponse);
const decodeRecord = Schema.decodeUnknownSync(RecordCatEventResponse);
const decodeJournal = Schema.decodeUnknownSync(CatJournalResponse);

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const mochi = { name: "Mochi", look: { model: "marmalade", coat: "natural" }, utcOffsetSeconds: 0 };

// The cases run in order on one world: each builds on the cat the one before left.
describe("the cat routes", () => {
  it("shows no cat before adoption, and refuses care for it", async () => {
    const before = decodeCat(await (await call("GET", "/v1/cat", "cleo")).json());
    expect(before.cat).toBeUndefined();
    expect(before.lastSeq).toBe(0);
    const pet = await call("POST", "/v1/cat/events", "cleo", {
      id: id(1),
      event: { _tag: "Petted" },
    });
    expect(pet.status).toBe(404);
  });

  it("adopts once, journals care from both, and keeps birth and nature on rename", async () => {
    const adopted = decodeCat(await (await call("PUT", "/v1/cat", "ana", mochi)).json());
    expect(adopted.cat?.name).toBe("Mochi");

    const fed = await call("POST", "/v1/cat/events", "ben", {
      id: id(1),
      event: { _tag: "Fed", grams: 30 },
    });
    expect(fed.status).toBe(200);
    const recorded = decodeRecord(await fed.json());
    expect(recorded.entry).toEqual({
      seq: 1,
      id: id(1),
      by: "ben",
      at: recorded.entry.at,
      event: { _tag: "Fed", grams: 30 },
    });

    const again = decodeRecord(
      await (
        await call("POST", "/v1/cat/events", "ben", { id: id(1), event: { _tag: "Petted" } })
      ).json(),
    );
    expect(again.entry).toEqual(recorded.entry);
    // The same id from the other partner is a different event under a taken id.
    const taken = await call("POST", "/v1/cat/events", "ana", {
      id: id(1),
      event: { _tag: "Petted" },
    });
    expect(taken.status).toBe(400);

    const renamed = decodeCat(
      await (await call("PUT", "/v1/cat", "ben", { ...mochi, name: "Pirozhok" })).json(),
    );
    expect(renamed.cat).toEqual({ ...adopted.cat, name: "Pirozhok" });
    expect(renamed.lastSeq).toBe(1);
  });

  it("journals a note sent to an adopted cat as one NoteShared entry", async () => {
    const sent = await call("POST", "/v1/notes", "ana", {
      _tag: "Text",
      key: id(77),
      text: "hi",
    });
    expect(sent.status).toBe(200);
    const journal = decodeJournal(
      await (await call("GET", "/v1/cat/journal?after=1", "ben")).json(),
    );
    expect(journal.entries.map((e) => [e.seq, e.id, e.by, e.event._tag])).toEqual([
      [2, id(77), "ana", "NoteShared"],
    ]);
  });

  it("keeps each couple's cat to itself, and answers 404 to someone with no pair", async () => {
    const other = decodeJournal(await (await call("GET", "/v1/cat/journal", "dan")).json());
    expect(other.entries).toEqual([]);
    expect((await call("GET", "/v1/cat", "eve")).status).toBe(404);
    expect((await call("PUT", "/v1/cat", "eve", mochi)).status).toBe(404);
  });

  it.each([
    ["a note from a phone", { id: id(5), event: { _tag: "NoteShared", note: "n", kind: "Text" } }],
    ["a meal too large", { id: id(5), event: { _tag: "Fed", grams: 5000 } }],
    ["no id", { event: { _tag: "Petted" } }],
  ])("answers 400 to %s", async (_, body) => {
    expect((await call("POST", "/v1/cat/events", "ana", body)).status).toBe(400);
  });

  it.each([
    ["an empty name", { ...mochi, name: "  " }],
    ["a name too long", { ...mochi, name: "M".repeat(25) }],
    ["an offset past a day", { ...mochi, utcOffsetSeconds: 15 * 3600 }],
  ])("refuses to save %s", async (_, body) => {
    expect((await call("PUT", "/v1/cat", "ana", body)).status).toBe(400);
  });
});
