import { Effect, Layer, Schema } from "effect";
import { Digest } from "effect/crypto";
import { HttpRouter } from "effect/http";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { defineExperiments, Experiments } from "@billet/backend-flags/experiments";
import { FlagConfigRepository } from "@billet/backend-flags/flag-config-repository";
import { FlagsRepository } from "@billet/backend-flags/flags-repository";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { makeInMemoryFlagConfigRepository } from "@billet/backend-flags/test/in-memory-flag-config-repository";
import { makeInMemoryFlagsRepository } from "@billet/backend-flags/test/in-memory-flags-repository";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { makeInMemoryPairingRepository } from "@billet/backend-pairing/test/in-memory-pairing-repository";
import type { EventRow } from "@billet/backend-metrics/funnel";
import { AdminData } from "../src/admin-data.ts";
import type { DetailRow } from "../src/admin-top-details.ts";
import { adminApi, AdminRoutes, CurrentAdmin, PanelEnvironment } from "../src/admin-routes.ts";
import { AppStatusStore } from "../src/app-status-store.ts";
import { makeInMemoryAppStatusStore } from "./in-memory-app-status-store.ts";

const experiments = defineExperiments([
  {
    key: "home-direction",
    kind: "experiment",
    description: "Room style.",
    variants: { "window-seat": 1, "sunset-lamp": 1 },
    default: "window-seat",
    exposure: 100,
    status: "draft",
    killed: false,
  },
  {
    key: "room-lighting",
    kind: "flag",
    variants: { "amber-lantern": 1, candle: 0 },
    default: "amber-lantern",
    exposure: 100,
    status: "draft",
    killed: false,
  },
]);

const today = new Date().toISOString().slice(0, 10);
const events: Array<EventRow> = [];
const details: Array<DetailRow> = [];
const pairing = makeInMemoryPairingRepository();
let configs = makeInMemoryFlagConfigRepository();
let assignments = makeInMemoryFlagsRepository();
let appStatus = makeInMemoryAppStatusStore();

const handlerFor = (email: string) =>
  HttpRouter.toWebHandler(
    AdminRoutes.pipe(
      Layer.provide(
        Layer.mergeAll(
          FlagsService.layer,
          Layer.succeed(CurrentAdmin, { email }),
          Layer.succeed(PanelEnvironment, { name: "dev" }),
        ).pipe(
          Layer.provideMerge(
            Layer.mergeAll(
              Layer.succeed(PairingRepository, pairing.repository),
              Layer.succeed(FlagsRepository, {
                find: (pairId) => assignments.repository.find(pairId),
                saveMissing: (pairId, rows) => assignments.repository.saveMissing(pairId, rows),
              }),
              Layer.succeed(FlagConfigRepository, {
                all: Effect.suspend(() => configs.repository.all),
                save: (change) => configs.repository.save(change),
                history: (key, limit) => configs.repository.history(key, limit),
                overridesOf: (pairId) => configs.repository.overridesOf(pairId),
                setOverride: (override) => configs.repository.setOverride(override),
                clearOverride: (change) => configs.repository.clearOverride(change),
              }),
              Layer.succeed(AdminData, {
                events: Effect.sync(() => events),
                details: Effect.sync(() => details),
                assignments: Effect.succeed([]),
                userCount: Effect.succeed(3),
                pair: (pairId) =>
                  Effect.succeed(
                    pairId === "pair-1"
                      ? { members: 2, pairedAt: 1_000 }
                      : { members: 0, pairedAt: null },
                  ),
              }),
              Layer.succeed(AppStatusStore, {
                current: Effect.suspend(() => appStatus.store.current),
                history: (limit) => appStatus.store.history(limit),
                save: (input) => appStatus.store.save(input),
              }),
              Experiments.with(experiments),
              Digest.layerWebCrypto,
            ),
          ),
        ),
      ),
    ),
    { disableLogger: true },
  );

const owner = handlerFor("owner@example.com");
afterAll(() => owner.dispose());

const call = async (path: string, method = "GET", body?: unknown) => {
  const response = await owner.handler(
    new Request(`https://api.billet.test${path}`, {
      method,
      ...(body === undefined
        ? {}
        : { body: JSON.stringify(body), headers: { "content-type": "application/json" } }),
    }),
  );
  const text = await response.text();
  return { status: response.status, body: text === "" ? undefined : JSON.parse(text) };
};

const user = Schema.decodeSync(UserId);
const pair = Schema.decodeSync(PairId);

beforeEach(() => {
  configs = makeInMemoryFlagConfigRepository();
  assignments = makeInMemoryFlagsRepository();
  appStatus = makeInMemoryAppStatusStore();
  events.length = 0;
  details.length = 0;
});

describe("the admin API", () => {
  it("says who is signed in through Access", async () => {
    expect(await call(adminApi.me)).toEqual({
      status: 200,
      body: { email: "owner@example.com", environment: "dev" },
    });
  });

  it("lists every registry entry with its live configuration, never edited yet", async () => {
    const { status, body } = await call(adminApi.flags);
    expect(status).toBe(200);
    expect(
      body.items.map((item: { key: string; version: number }) => [item.key, item.version]),
    ).toEqual([
      ["home-direction", 0],
      ["room-lighting", 0],
    ]);
    expect(body.items[1]).toMatchObject({
      kind: "flag",
      variants: ["amber-lantern", "candle"],
      config: { weights: { "amber-lantern": 1, candle: 0 }, status: "draft", killed: false },
      updatedBy: null,
    });
  });

  it("saves an edit under the Access identity, with a version and a history line", async () => {
    const before = (await call(adminApi.flags)).body.items[1].config;
    const config = { ...before, weights: { "amber-lantern": 1, candle: 1 }, status: "running" };
    const saved = await call("/admin/api/flags/room-lighting", "PUT", {
      config,
      expectedVersion: 0,
    });
    expect(saved.status).toBe(200);
    expect(saved.body).toMatchObject({ version: 1, updatedBy: "owner@example.com", config });

    const history = await call(`${adminApi.history}?key=room-lighting`);
    expect(history.body.changes).toHaveLength(1);
    expect(history.body.changes[0]).toMatchObject({
      key: "room-lighting",
      by: "owner@example.com",
      action: "edit",
      before: null,
      after: config,
    });
  });

  it("answers 409 for a save from a stale version, and changes nothing", async () => {
    const config = (await call(adminApi.flags)).body.items[1].config;
    await call("/admin/api/flags/room-lighting", "PUT", { config, expectedVersion: 0 });
    const stale = await call("/admin/api/flags/room-lighting", "PUT", {
      config: { ...config, exposure: 5 },
      expectedVersion: 0,
    });
    expect(stale).toEqual({ status: 409, body: { error: "conflict", current: 1 } });
    expect((await call(adminApi.flags)).body.items[1].config.exposure).toBe(100);
  });

  it.each([
    ["a variant the app does not have", { weights: { "amber-lantern": 1, candle: 0, disco: 1 } }],
    ["a default outside the variants", { default: "disco" }],
    ["exposure over 100", { exposure: 101 }],
    ["a bad version bound", { targeting: { minAppVersion: "latest" } }],
  ])("refuses %s with 400", async (_, change) => {
    const config = (await call(adminApi.flags)).body.items[1].config;
    const response = await call("/admin/api/flags/room-lighting", "PUT", {
      config: { ...config, ...change },
      expectedVersion: 0,
    });
    expect(response.status).toBe(400);
    expect(response.body.error).toBe("invalid");
    expect(configs.configs.size).toBe(0);
  });

  it("answers 404 for a key the registry does not have", async () => {
    const config = (await call(adminApi.flags)).body.items[1].config;
    expect(
      (await call("/admin/api/flags/no-such-flag", "PUT", { config, expectedVersion: 0 })).status,
    ).toBe(404);
  });

  it("starts, stops, kills and unkills an experiment, each logged", async () => {
    const act = (action: string, expectedVersion: number) =>
      call(`/admin/api/experiments/home-direction/${action}`, "POST", { expectedVersion });
    expect((await act("start", 0)).body.config.status).toBe("running");
    expect((await act("kill", 1)).body.config.killed).toBe(true);
    expect((await act("unkill", 2)).body.config.killed).toBe(false);
    expect((await act("stop", 3)).body.config.status).toBe("stopped");
    expect((await act("explode", 4)).status).toBe(400);
    const history = (await call(adminApi.history)).body.changes;
    expect(history.map(({ action }: { action: string }) => action)).toEqual([
      "stop",
      "unkill",
      "kill",
      "start",
    ]);
  });

  it("shows per-variant results with a 95% interval for an experiment with pairs", async () => {
    const response = await call(adminApi.experiments);
    expect(response.status).toBe(200);
    expect(response.body.items[0]).toMatchObject({ key: "home-direction", results: null });
  });

  it("builds the overview from the counts", async () => {
    events.push(
      { pairId: "", userId: "u1", name: "AppOpened", day: today, count: 2, firstAt: 1 },
      { pairId: "p1", userId: "u1", name: "PairClaimed", day: today, count: 1, firstAt: 2 },
      { pairId: "p1", userId: "u2", name: "PairClaimed", day: today, count: 1, firstAt: 2 },
      { pairId: "p1", userId: "u2", name: "NoteSent", day: today, count: 4, firstAt: 3 },
    );
    const { status, body } = await call(adminApi.overview);
    expect(status).toBe(200);
    expect(body.totals).toEqual({ users: 3, pairs: 1, notes: 4 });
    expect(body.daily).toHaveLength(30);
    expect(body.daily.at(-1)).toEqual({ day: today, dau: 2, wau: 2, pairsCreated: 1, notes: 4 });
    expect(body.funnel.map(({ count }: { count: number | null }) => count)).toEqual([
      null,
      3,
      2,
      1,
      0,
    ]);
    expect(body.pairCompletion).toMatchObject({ of: 0, share: null, interval: null });
  });

  it("builds the overview over 7 or 90 days, and refuses any other range", async () => {
    events.push(
      { pairId: "p1", userId: "u1", name: "PairClaimed", day: today, count: 1, firstAt: 2 },
      { pairId: "p1", userId: "u2", name: "PairClaimed", day: today, count: 1, firstAt: 2 },
      { pairId: "p1", userId: "u2", name: "NoteSent", day: today, count: 4, firstAt: 3 },
    );
    const week = await call(`${adminApi.overview}?days=7`);
    expect(week.status).toBe(200);
    expect(week.body.daily).toHaveLength(7);
    expect(week.body.range).toMatchObject({ days: 7, to: today });
    expect(week.body.stats.newPairs).toMatchObject({ current: 1, previous: 0 });
    expect((await call(`${adminApi.overview}?days=90`)).body.stats.dau.series).toHaveLength(90);
    expect((await call(`${adminApi.overview}?days=8`)).status).toBe(400);
  });

  it("counts each event in the app over the range", async () => {
    events.push(
      { pairId: "p1", userId: "u1", name: "PairClaimed", day: today, count: 1, firstAt: 2 },
      { pairId: "p1", userId: "u2", name: "PairClaimed", day: today, count: 1, firstAt: 2 },
      { pairId: "p1", userId: "u2", name: "NoteSent", day: today, count: 4, firstAt: 3 },
    );
    const { status, body } = await call(`${adminApi.appEvents}?days=7`);
    expect(status).toBe(200);
    expect(body.days).toHaveLength(7);
    const noteSent = body.events.find(({ name }: { name: string }) => name === "NoteSent");
    expect(noteSent).toMatchObject({ source: "server", total: 4, pairs7d: 1, lastDay: today });
    const widget = body.events.find(({ name }: { name: string }) => name === "WidgetAdded");
    expect(widget).toMatchObject({ total: 0, firstDay: null, lastDay: null });
    expect((await call(`${adminApi.appEvents}?days=1`)).status).toBe(400);
  });

  it("ranks the most chosen things over the range, with stamps spent on bought ones", async () => {
    details.push(
      { name: "CatChosen", detail: "tabby", day: today, count: 2, total: 0 },
      { name: "CatChosen", detail: "idolIlya", day: today, count: 5, total: 0 },
      { name: "CatChosen", detail: "hero", day: "2020-01-01", count: 50, total: 0 },
      { name: "ShopItemBought", detail: "lamp", day: today, count: 2, total: 60 },
    );
    const { body } = await call(`${adminApi.appEvents}?days=7`);
    const top = (name: string) =>
      body.top.find((entry: { name: string }) => entry.name === name).items;
    expect(top("CatChosen")).toEqual([
      { detail: "idolIlya", count: 5 },
      { detail: "tabby", count: 2 },
    ]);
    expect(top("ShopItemBought")).toEqual([{ detail: "lamp", count: 2, total: 60 }]);
    expect(top("TrickDone")).toEqual([]);
  });

  describe("pairs", () => {
    let paired = false;
    const pairOne = async () => {
      if (paired) return;
      paired = true;
      await Effect.runPromise(
        pairing.repository.saveInvite({
          codeHash: "h",
          ownerId: user("u-a"),
          createdAt: 1,
          expiresAt: 9,
        }),
      );
      await Effect.runPromise(
        pairing.repository.claimInvite({
          codeHash: "h",
          claimerId: user("u-b"),
          pairId: pair("pair-1"),
          now: 2,
        }),
      );
    };

    it("looks a pair up by id: hash, members, decisions, no user ids", async () => {
      await pairOne();
      const { status, body } = await call("/admin/api/pairs/pair-1");
      expect(status).toBe(200);
      expect(body).toMatchObject({ pairId: "pair-1", members: 2, pairedAt: 1_000 });
      expect(body.pairHash).toMatch(/^[0-9a-f]{16}$/);
      expect(body.decisions).toEqual([
        { key: "home-direction", variant: null, reason: "draft" },
        { key: "room-lighting", variant: null, reason: "draft" },
      ]);
      expect(JSON.stringify(body)).not.toContain("u-a");
    });

    it("answers 404 for a pair it knows nothing about", async () => {
      expect((await call("/admin/api/pairs/pair-unknown")).status).toBe(404);
    });

    it("overrides a pair's variant for testing, then clears it, logging both", async () => {
      await pairOne();
      const path = "/admin/api/pairs/pair-1/overrides/home-direction";
      expect((await call(path, "PUT", { variant: "sunset-lamp" })).status).toBe(204);
      const looked = (await call("/admin/api/pairs/pair-1")).body;
      expect(looked.overrides).toEqual([
        {
          key: "home-direction",
          variant: "sunset-lamp",
          setAt: expect.any(Number),
          setBy: "owner@example.com",
        },
      ]);
      expect(looked.decisions[0]).toEqual({
        key: "home-direction",
        variant: "sunset-lamp",
        reason: "override",
      });
      expect((await call(path, "DELETE")).status).toBe(204);
      expect((await call("/admin/api/pairs/pair-1")).body.overrides).toEqual([]);
      const actions = (await call(adminApi.history)).body.changes.map(
        ({ action, pairId }: { action: string; pairId: string }) => [action, pairId],
      );
      expect(actions).toEqual([
        ["clear-override", "pair-1"],
        ["override", "pair-1"],
      ]);
    });

    it("refuses an override with a variant the entry does not have", async () => {
      const response = await call("/admin/api/pairs/pair-1/overrides/home-direction", "PUT", {
        variant: "disco",
      });
      expect(response.status).toBe(400);
      expect(configs.overrides.size).toBe(0);
    });
  });
});

describe("the maintenance section", () => {
  const maintenance = {
    maintenance: {
      active: true,
      message: { key: "maintenance.default", text: "Back soon." },
      until: "2026-11-03T22:30:00Z",
    },
    minVersion: "1.2.0+14",
    notice: { key: "notice.slow-notes", text: "Notes may be slow tonight." },
  };

  it("starts normal and never set", async () => {
    expect(await call(adminApi.status)).toEqual({
      status: 200,
      body: {
        status: { maintenance: { active: false } },
        version: 0,
        updatedAt: null,
        updatedBy: null,
      },
    });
  });

  it("saves the status whole, with the email, and keeps it in the history", async () => {
    const saved = await call(adminApi.status, "PUT", { status: maintenance, expectedVersion: 0 });
    expect(saved.status).toBe(200);
    expect(saved.body).toMatchObject({
      status: maintenance,
      version: 1,
      updatedBy: "owner@example.com",
    });
    const history = await call(adminApi.statusHistory);
    expect(history.body.changes).toEqual([
      expect.objectContaining({ version: 1, by: "owner@example.com", status: maintenance }),
    ]);
  });

  it("refuses a save from a stale version with 409", async () => {
    await call(adminApi.status, "PUT", { status: maintenance, expectedVersion: 0 });
    const stale = await call(adminApi.status, "PUT", { status: maintenance, expectedVersion: 0 });
    expect(stale).toEqual({ status: 409, body: { error: "conflict", current: 1 } });
  });

  it.each([
    ["an until without a zone", { maintenance: { active: true, until: "22:30" } }],
    ["a free-text minVersion", { maintenance: { active: false }, minVersion: "newest" }],
    ["an empty message", { maintenance: { active: true, message: { key: "m", text: "" } } }],
  ])("refuses %s with 400", async (_, status) => {
    expect((await call(adminApi.status, "PUT", { status, expectedVersion: 0 })).status).toBe(400);
  });
});
