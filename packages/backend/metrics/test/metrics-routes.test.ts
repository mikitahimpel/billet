import { Effect, Layer, Redacted, Schema } from "effect";
import { Digest } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { AuthRejected, AuthUnavailable } from "@billet/backend-auth/auth-error";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { maxEventsPerRequest } from "@billet/contracts-http-api/events";
import { clientHeaders, routes } from "@billet/contracts-http-api/routes";
import { type AnalyticsPoint, EventSink, pairHashOf, PairVariants } from "../src/analytics.ts";
import { Metrics } from "../src/metrics.ts";
import { MetricsRepository } from "../src/metrics-repository.ts";
import { MetricsRoutes } from "../src/metrics-routes.ts";
import { makeInMemoryMetricsRepository } from "./in-memory-metrics-repository.ts";

describe("events route", () => {
  const tokenOf = (name: string) => name.padEnd(43, "x");
  const user = (name: string) => Schema.decodeSync(UserId)(tokenOf(name));
  const principal = (token: string): Principal => ({
    userId: Schema.decodeSync(UserId)(token),
    deviceId: Schema.decodeSync(DeviceId)(`device-${token}`),
    sessionHash: `hash-${token}`,
  });
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
        if (raw.startsWith("down")) return Effect.fail(new AuthUnavailable({ reason: "fake" }));
        return Effect.succeed(principal(raw));
      },
    }),
  );
  const pairs = makeInMemoryPairingRepository();
  const metrics = makeInMemoryMetricsRepository();
  const points: Array<AnalyticsPoint> = [];
  const RecordingSink = Layer.succeed(EventSink, {
    write: (point) => Effect.sync(() => void points.push(point)),
  });
  const FixedVariants = Layer.succeed(PairVariants, {
    of: (pairId) =>
      Effect.succeed(
        pairId === "pair-1"
          ? [
              { key: "home-direction", variant: "sunset-lamp" },
              { key: "glow", variant: "strong" },
            ]
          : [],
      ),
  });
  const { handler, dispose } = HttpRouter.toWebHandler(
    MetricsRoutes.pipe(
      Layer.provide(
        Layer.mergeAll(
          FakeAuth,
          Metrics.layer.pipe(Layer.provide(Layer.succeed(MetricsRepository, metrics.repository))),
          Layer.succeed(PairingRepository, pairs.repository),
          RecordingSink,
          FixedVariants,
          Digest.layerWebCrypto,
        ),
      ),
    ),
    { disableLogger: true },
  );
  afterAll(() => dispose());

  const post = (body: unknown, token?: string, extra: Record<string, string> = {}) =>
    handler(
      new Request(`http://billet.test${routes.reportEvents.path}`, {
        method: routes.reportEvents.method,
        headers: {
          "content-type": "application/json",
          ...(token === undefined ? {} : { authorization: `Bearer ${tokenOf(token)}` }),
          ...extra,
        },
        body: JSON.stringify(body),
      }),
    );

  it("needs a signed-in caller", async () => {
    expect((await post({ events: [] })).status).toBe(401);
    expect((await post({ events: [] }, "rejected-x")).status).toBe(401);
    expect(metrics.rows.size).toBe(0);
  });

  it("counts the events it is sent, for the caller, without a pair before pairing", async () => {
    const response = await post({ events: ["AppOpened", "WidgetAdded"] }, "ana");
    expect(response.status).toBe(204);
    expect(
      [...metrics.rows.values()].map(({ name, pairId, userId }) => [name, pairId, userId]),
    ).toEqual([
      ["AppOpened", "", user("ana")],
      ["WidgetAdded", "", user("ana")],
    ]);
  });

  it("files them under the caller's pair once paired", async () => {
    await Effect.runPromise(
      pairs.repository.saveInvite({
        codeHash: "h",
        ownerId: user("ben"),
        createdAt: 1,
        expiresAt: 10,
      }),
    );
    await Effect.runPromise(
      pairs.repository.claimInvite({
        codeHash: "h",
        claimerId: user("cal"),
        pairId: Schema.decodeSync(PairId)("pair-1"),
        now: 2,
      }),
    );
    await post({ events: ["OpeningWatched"] }, "cal");
    const row = [...metrics.rows.values()].find(({ name }) => name === "OpeningWatched");
    expect(row?.pairId).toBe("pair-1");
  });

  it.each([
    ["a name the server records itself", { events: ["NoteSent"] }],
    ["an unknown name", { events: ["Anything"] }],
    [
      "too many events",
      { events: Array.from({ length: maxEventsPerRequest + 1 }, () => "AppOpened") },
    ],
    ["no events field", {}],
    ["an object with a name the server records itself", { events: [{ name: "PairClaimed" }] }],
    ["a detail on a name that takes none", { events: [{ name: "CatPetted", detail: "tabby" }] }],
    ["a missing detail where one is needed", { events: [{ name: "CatChosen" }] }],
    ["a detail outside the closed list", { events: [{ name: "NoteOpened", detail: "email" }] }],
    ["a detail that is free text", { events: [{ name: "CatChosen", detail: "my cat Tom" }] }],
    ["an over-long detail", { events: [{ name: "CatChosen", detail: "a".repeat(41) }] }],
    [
      "a value on a name that takes none",
      { events: [{ name: "CatChosen", detail: "tabby", value: 3 }] },
    ],
    ["a negative price", { events: [{ name: "ShopItemBought", detail: "lamp", value: -1 }] }],
    ["a fractional price", { events: [{ name: "ShopItemBought", detail: "lamp", value: 1.5 }] }],
  ])("refuses %s", async (_, body) => {
    const before = metrics.rows.size;
    expect((await post(body, "ana")).status).toBe(400);
    expect(metrics.rows.size).toBe(before);
  });

  it("counts detailed events like bare ones, and their details apart from the person", async () => {
    const response = await post(
      {
        events: [
          "AppOpened",
          { name: "CatChosen", detail: "idolIlya" },
          { name: "ShopItemBought", detail: "fairy-lights", value: 40 },
          { name: "CatPetted" },
          { name: "CatPetted", note: "ignored" },
        ],
      },
      "dan",
    );
    expect(response.status).toBe(204);
    const dan = [...metrics.rows.values()].filter(({ userId }) => userId === user("dan"));
    expect(dan.map(({ name, count }) => [name, count]).toSorted()).toEqual([
      ["AppOpened", 1],
      ["CatChosen", 1],
      ["CatPetted", 2],
      ["ShopItemBought", 1],
    ]);
    expect([...metrics.details.values()]).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ name: "CatChosen", detail: "idolIlya", count: 1, total: 0 }),
        expect.objectContaining({ name: "ShopItemBought", detail: "fairy-lights", total: 40 }),
      ]),
    );
    expect(JSON.stringify([...metrics.details.values()])).not.toContain(user("dan"));
    expect(JSON.stringify([...metrics.rows.values()])).not.toContain("ignored");
  });

  it("ignores any other field in the body and stores none of it", async () => {
    const response = await post({ events: ["OpeningSkipped"], text: "a love letter" }, "ana");
    expect(response.status).toBe(204);
    expect(JSON.stringify([...metrics.rows.values()])).not.toContain("love letter");
  });

  it("stores no field beyond the fixed ones", () => {
    for (const row of metrics.rows.values()) {
      expect(Object.keys(row).toSorted()).toEqual([
        "appVersion",
        "count",
        "day",
        "firstAt",
        "lastAt",
        "name",
        "os",
        "pairId",
        "userId",
      ]);
    }
  });

  it("answers 204 for an empty list without touching storage", async () => {
    const before = metrics.rows.size;
    expect((await post({ events: [] }, "ana")).status).toBe(204);
    expect(metrics.rows.size).toBe(before);
  });

  describe("Analytics Engine", () => {
    const pairHash = () =>
      Effect.runPromise(
        pairHashOf(Schema.decodeSync(PairId)("pair-1")).pipe(Effect.provide(Digest.layerWebCrypto)),
      );

    it("writes each accepted event with the pair hashed, its variants, build and system", async () => {
      points.length = 0;
      const hash = await pairHash();
      const response = await post({ events: ["AppOpened", "WidgetAdded"] }, "cal", {
        [clientHeaders.appVersion]: "1.2.0+14",
        [clientHeaders.os]: "iOS 26.1",
      });
      expect(response.status).toBe(204);
      expect(points).toEqual([
        {
          name: "AppOpened",
          pairHash: hash,
          variants: "glow=strong,home-direction=sunset-lamp",
          appVersion: "1.2.0+14",
          os: "iOS 26.1",
        },
        {
          name: "WidgetAdded",
          pairHash: hash,
          variants: "glow=strong,home-direction=sunset-lamp",
          appVersion: "1.2.0+14",
          os: "iOS 26.1",
        },
      ]);
      expect(hash).toMatch(/^[0-9a-f]{16}$/);
      expect(JSON.stringify(points)).not.toContain("pair-1");
      expect(JSON.stringify(points)).not.toContain(tokenOf("cal"));
    });

    it("keeps the same build and system on the D1 count", async () => {
      await post({ events: ["ProfileOpened"] }, "cal", {
        [clientHeaders.appVersion]: "1.3.0+17",
        [clientHeaders.os]: "iOS 26.1",
      });
      const row = [...metrics.rows.values()].find(({ name }) => name === "ProfileOpened");
      expect(row).toMatchObject({ appVersion: "1.3.0+17", os: "iOS 26.1" });
    });

    it("writes an unpaired caller with an empty pair and no variants", async () => {
      points.length = 0;
      await post({ events: ["AppOpened"] }, "ana");
      expect(points).toEqual([
        { name: "AppOpened", pairHash: "", variants: "", appVersion: "unknown", os: "unknown" },
      ]);
    });

    it.each([
      ["free text", "my name is Ana"],
      ["an email", "ana@example.com"],
      ["an over-long version", "1.2.3.4.5"],
    ])("reads %s in the build headers as unknown", async (_, value) => {
      points.length = 0;
      await post({ events: ["AppOpened"] }, "ana", {
        [clientHeaders.appVersion]: value,
        [clientHeaders.os]: value,
      });
      expect(points[0]).toMatchObject({ appVersion: "unknown", os: "unknown" });
    });

    it("adds the detail and the price to the point when the event has them", async () => {
      points.length = 0;
      await post(
        { events: [{ name: "ShopItemBought", detail: "lamp", value: 25 }, "AppOpened"] },
        "ana",
      );
      expect(points).toEqual([
        {
          name: "ShopItemBought",
          pairHash: "",
          variants: "",
          appVersion: "unknown",
          os: "unknown",
          detail: "lamp",
          value: 25,
        },
        { name: "AppOpened", pairHash: "", variants: "", appVersion: "unknown", os: "unknown" },
      ]);
      points.length = 0;
    });

    it("writes nothing for a refused request", async () => {
      points.length = 0;
      await post({ events: ["NoteSent"] }, "ana");
      await post({ events: ["AppOpened"] });
      expect(points).toEqual([]);
    });

    it("holds only the documented fields", () => {
      for (const point of points) {
        expect(Object.keys(point).toSorted()).toEqual([
          "appVersion",
          "name",
          "os",
          "pairHash",
          "variants",
        ]);
      }
    });
  });
});
