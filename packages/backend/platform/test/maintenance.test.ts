import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { Schema } from "effect";
import { beforeEach, describe, expect, it } from "vitest";
import { accessJwtHeader } from "@billet/backend-admin/access";
import {
  signAccess,
  signAgent,
  teamKeys,
  testAccess,
} from "@billet/backend-admin/test/access-tokens";
import { routes } from "@billet/contracts-http-api/routes";
import {
  type AppStatus,
  MaintenanceResponse,
  StatusResponse,
} from "@billet/contracts-http-api/status";
import { socketRoute } from "@billet/contracts-realtime/socket-route";
import { respondAdmin } from "../src/admin-fetch.ts";
import { respondApi } from "../src/api-fetch.ts";
import { retryAfterSeconds, gateRequest } from "../src/maintenance-gate.ts";
import { readServedStatus, statusHistoryKey, statusKey } from "../src/app-status-live.ts";
import type { WorkerEnv } from "../src/worker-env.ts";
import { resetDirectory } from "./directory-migrations.ts";
import { testExperiments } from "./test-experiments.ts";

const origin = "https://api.billet.test";

const maintenance: AppStatus = {
  maintenance: {
    active: true,
    message: { key: "maintenance.default", text: "billet is resting for a little while." },
    until: "2026-11-03T22:30:00Z",
  },
  minVersion: "1.0",
};

/** A database that fails every call, as D1 does when it is down. */
const brokenDatabase = new Proxy({} as D1Database, {
  get: () => () => {
    throw new Error("D1 is down");
  },
});

const setStatus = (status: AppStatus) =>
  env.STATUS.put(
    statusKey,
    JSON.stringify({ status, version: 1, updatedAt: 1, updatedBy: "owner@example.com" }),
  );

const api = async (path: string, init: RequestInit = {}, workerEnv: WorkerEnv = env) => {
  const ctx = createExecutionContext();
  const response = await respondApi(
    new Request(`${origin}${path}`, init),
    workerEnv,
    ctx,
    testExperiments,
  );
  await waitOnExecutionContext(ctx);
  return response;
};

beforeEach(async () => {
  await resetDirectory();
  await env.STATUS.delete(statusKey);
  await env.STATUS.delete(statusHistoryKey);
});

describe("GET /v1/status", () => {
  it("is the normal status when nothing was ever set, without a session", async () => {
    const response = await api(routes.getStatus.path);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(Schema.decodeUnknownSync(StatusResponse)(await response.json())).toEqual({
      status: { maintenance: { active: false } },
    });
  });

  it("is served while D1 is unavailable", async () => {
    await setStatus(maintenance);
    const response = await api(routes.getStatus.path, {}, { ...env, DB: brokenDatabase });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: maintenance });
  });

  it("reads as normal when the Worker has no status binding, or the value is not a status", async () => {
    const { STATUS: _, ...unbound } = env;
    expect(await (await api(routes.getStatus.path, {}, unbound)).json()).toEqual({
      status: { maintenance: { active: false } },
    });
    await env.STATUS.put(statusKey, "not json");
    expect(await readServedStatus(env.STATUS)).toEqual({ maintenance: { active: false } });
  });
});

describe("during maintenance", () => {
  beforeEach(() => setStatus(maintenance));

  it.each([
    [routes.sendNote.method, routes.sendNote.path],
    [routes.authChallenge.method, routes.authChallenge.path],
    [routes.createInvite.method, routes.createInvite.path],
    [routes.unpair.method, routes.unpair.path],
    [routes.registerPushToken.method, routes.registerPushToken.path],
    [routes.reportEvents.method, routes.reportEvents.path],
  ])(
    "refuses %s %s with 503, Retry-After and the status, without touching D1",
    async (method, path) => {
      const response = await api(path, { method }, { ...env, DB: brokenDatabase });
      expect(response.status).toBe(503);
      expect(Number(response.headers.get("retry-after"))).toBeGreaterThanOrEqual(30);
      expect(Schema.decodeUnknownSync(MaintenanceResponse)(await response.json())).toEqual({
        error: "maintenance",
        status: maintenance,
      });
    },
  );

  it("refuses the realtime socket, which carries writes", async () => {
    const response = await api(socketRoute.path, { headers: { upgrade: "websocket" } });
    expect(response.status).toBe(503);
  });

  it("lets reads through to the API", async () => {
    expect((await api(routes.listNotes.path)).status).toBe(401);
  });

  it("writes go through again once it is switched off", async () => {
    await setStatus({ maintenance: { active: false } });
    expect((await api(routes.authChallenge.path, { method: "POST" })).status).toBe(200);
  });
});

describe("Retry-After", () => {
  const at = Date.parse("2026-11-03T22:00:00Z");
  it.each([
    [undefined, 300],
    ["2026-11-03T22:30:00Z", 1_800],
    ["2026-11-03T22:00:10Z", 30],
    ["2026-11-04T09:00:00Z", 3_600],
    ["2026-11-03T21:00:00Z", 30],
  ])("is %s → %i s", (until, seconds) => {
    const status: AppStatus = {
      maintenance: { active: true, ...(until === undefined ? {} : { until }) },
    };
    expect(retryAfterSeconds(status, at)).toBe(seconds);
  });

  it("is only on refused writes", () => {
    const read = gateRequest(new Request(`${origin}/v1/notes`), maintenance, at);
    expect(read).toBeUndefined();
  });
});

describe("the admin panel's maintenance section", () => {
  const configured: WorkerEnv = {
    ...env,
    ACCESS_TEAM_DOMAIN: testAccess.teamDomain,
    ACCESS_AUD: testAccess.audience,
    ACCESS_AGENT_AUD: testAccess.agentAudience,
  };
  const admin = async (
    path: string,
    init: RequestInit & { token: string },
    workerEnv = configured,
  ) => {
    const { token, ...rest } = init;
    const headers = new Headers(rest.headers);
    headers.set(accessJwtHeader, token);
    const ctx = createExecutionContext();
    const response = await respondAdmin(
      new Request(`${origin}${path}`, { ...rest, headers }),
      workerEnv,
      ctx,
      {
        experiments: testExperiments,
        accessKeys: teamKeys,
      },
    );
    await waitOnExecutionContext(ctx);
    return response;
  };
  const save = async (status: AppStatus, expectedVersion: number, workerEnv = configured) =>
    admin(
      "/admin/api/status",
      {
        method: "PUT",
        token: await signAccess(),
        body: JSON.stringify({ status, expectedVersion }),
        headers: { "content-type": "application/json", origin, "sec-fetch-site": "same-origin" },
      },
      workerEnv,
    );

  it("switches maintenance on while D1 is down, and the API serves it", async () => {
    const saved = await save(maintenance, 0, { ...configured, DB: brokenDatabase });
    expect(saved.status).toBe(200);
    expect(await saved.json()).toMatchObject({ version: 1, updatedBy: "owner@example.com" });
    expect(await (await api(routes.getStatus.path)).json()).toEqual({ status: maintenance });
    const history = await admin("/admin/api/status/history", { token: await signAccess() });
    expect(await history.json()).toEqual({
      changes: [
        expect.objectContaining({ version: 1, by: "owner@example.com", status: maintenance }),
      ],
    });
  });

  it("refuses a stale save with 409", async () => {
    await save(maintenance, 0);
    expect((await save({ maintenance: { active: false } }, 0)).status).toBe(409);
  });

  it("shows the status to agents, who can't change it", async () => {
    await save(maintenance, 0);
    const read = await admin("/admin/api/agent/status", { token: await signAgent() });
    expect(read.status).toBe(200);
    expect(await read.json()).toMatchObject({ status: maintenance, version: 1 });
    const write = await admin("/admin/api/status", {
      method: "PUT",
      token: await signAgent(),
      body: JSON.stringify({ status: { maintenance: { active: false } }, expectedVersion: 1 }),
      headers: { "content-type": "application/json", origin, "sec-fetch-site": "same-origin" },
    });
    expect(write.status).toBe(403);
    expect(await readServedStatus(env.STATUS)).toEqual(maintenance);
  });
});
