import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { accessJwtHeader } from "@billet/backend-admin/access";
import {
  signAccess,
  signAgent,
  teamKeys,
  testAgent,
  testAccess,
  unsignedAccess,
} from "@billet/backend-admin/test/access-tokens";
import { respondAdmin } from "../src/admin-fetch.ts";
import type { WorkerEnv } from "../src/worker-env.ts";
import { resetDirectory } from "./directory-migrations.ts";
import { testExperiments } from "./test-experiments.ts";

const origin = "https://api.billet.test";
const configured: WorkerEnv = {
  ...env,
  ACCESS_TEAM_DOMAIN: testAccess.teamDomain,
  ACCESS_AUD: testAccess.audience,
  ACCESS_AGENT_AUD: testAccess.agentAudience,
};

const admin = async (
  path: string,
  init: RequestInit & { token?: string | null } = {},
  workerEnv: WorkerEnv = configured,
) => {
  const { token, ...rest } = init;
  const headers = new Headers(rest.headers);
  if (token !== null) headers.set(accessJwtHeader, token ?? (await signAccess()));
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

beforeEach(resetDirectory);

describe("the admin panel behind Cloudflare Access", () => {
  const paths = [
    "/admin",
    "/admin/app.js",
    "/admin/lib.js",
    "/admin/api/me",
    "/admin/api/flags",
    "/admin/nothing",
  ];

  it.each(paths)("refuses %s without an Access token with a bare 403", async (path) => {
    const response = await admin(path, { token: null });
    expect(response.status).toBe(403);
    expect(await response.text()).toBe("Forbidden");
  });

  it.each([
    ["expired", { exp: Math.floor(Date.now() / 1000) - 60 }],
    ["for another audience", { aud: ["b".repeat(64)] }],
    ["from another team", { iss: "https://other.cloudflareaccess.com" }],
  ])("refuses a token that is %s with 403", async (_, overrides) => {
    const response = await admin("/admin/api/me", { token: await signAccess(overrides) });
    expect(response.status).toBe(403);
  });

  it("refuses an unsigned token", async () => {
    expect((await admin("/admin/api/me", { token: unsignedAccess() })).status).toBe(403);
  });

  it("fails closed when the Worker has no Access configuration, even with a valid token", async () => {
    expect((await admin("/admin/api/me", {}, env as WorkerEnv)).status).toBe(403);
    expect(
      (await admin("/admin/api/me", {}, { ...configured, ACCESS_AUD: "not-an-aud" })).status,
    ).toBe(403);
  });

  it("is refused through the real Worker too, which has no Access configuration in tests", async () => {
    const response = await exports.default.fetch(
      new Request(`${origin}/admin/api/me`, {
        headers: { [accessJwtHeader]: await signAccess() },
      }),
    );
    expect(response.status).toBe(403);
  });

  it("serves the page, script and style with a strict policy to a valid token", async () => {
    const page = await admin("/admin");
    expect(page.status).toBe(200);
    expect(page.headers.get("content-type")).toContain("text/html");
    expect(page.headers.get("content-security-policy")).toContain("default-src 'none'");
    expect(page.headers.get("content-security-policy")).toContain("frame-ancestors 'none'");
    expect(page.headers.get("cache-control")).toBe("no-store");
    expect(await page.text()).toContain("/admin/app.js");
    expect((await admin("/admin/app.js")).headers.get("content-type")).toContain("javascript");
    expect((await admin("/admin/app.css")).headers.get("content-type")).toContain("text/css");
    expect((await admin("/admin/lib.js")).headers.get("content-type")).toContain("javascript");
  });

  it("answers the API as the Access identity", async () => {
    const response = await admin("/admin/api/me", {
      token: await signAccess({ email: "o@example.com" }),
    });
    expect(await response.json()).toEqual({ email: "o@example.com", environment: "unknown" });
  });

  it("tells the panel which stage it is on", async () => {
    const response = await admin("/admin/api/me", {}, { ...configured, STAGE: "dev" });
    expect(await response.json()).toMatchObject({ environment: "dev" });
  });

  it("refuses a write from another site, and takes one from the panel's own origin", async () => {
    const flags = (await (await admin("/admin/api/flags")).json()) as {
      items: Array<{ key: string; config: unknown; version: number }>;
    };
    const split = flags.items.find(({ key }) => key === "split");
    const body = JSON.stringify({ config: split?.config, expectedVersion: 0 });
    const write = (headers: Record<string, string>) =>
      admin("/admin/api/flags/split", {
        method: "PUT",
        body,
        headers: { "content-type": "application/json", ...headers },
      });
    expect((await write({})).status).toBe(403);
    expect((await write({ origin: "https://evil.example" })).status).toBe(403);
    expect((await write({ origin, "sec-fetch-site": "cross-site" })).status).toBe(403);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM flag_configs").first("n")).toBe(0);
    const saved = await write({ origin, "sec-fetch-site": "same-origin" });
    expect(saved.status).toBe(200);
    const change = await env.DB.prepare("SELECT key, by, action FROM flag_changes").first();
    expect(change).toEqual({ key: "split", by: "owner@example.com", action: "edit" });
  });

  it("kills an experiment so the app stops getting it on its next read", async () => {
    const items = (await (await admin("/admin/api/experiments")).json()) as {
      items: Array<{ key: string; version: number }>;
    };
    expect(items.items.map(({ key }) => key)).toContain("split");
    const killed = await admin("/admin/api/experiments/split/kill", {
      method: "POST",
      body: JSON.stringify({ expectedVersion: 0 }),
      headers: { "content-type": "application/json", origin },
    });
    expect(killed.status).toBe(200);
    const row = await env.DB.prepare("SELECT config FROM flag_configs WHERE key = 'split'").first<{
      config: string;
    }>();
    expect(JSON.parse(row?.config ?? "{}").killed).toBe(true);
  });

  it("answers 404 for a pair it has never seen, looked up by id only", async () => {
    expect((await admin("/admin/api/pairs/no-such-pair")).status).toBe(404);
  });

  it("reads the overview from D1 without exposing an Apple subject", async () => {
    const response = await admin("/admin/api/overview");
    expect(response.status).toBe(200);
    const body = (await response.json()) as { totals: { users: number } };
    expect(body.totals.users).toBe(0);
  });
});

describe("the read-only agent API", () => {
  const reads = [
    "/admin/api/agent/overview",
    "/admin/api/agent/experiments",
    "/admin/api/agent/flags",
    "/admin/api/agent/flag-history",
    "/admin/api/agent/purchases",
    "/admin/api/agent/onboarding",
    "/admin/api/agent/retention",
    "/admin/api/agent/funnel?steps=AppOpened,NoteSent&window=day&unit=person",
    "/admin/api/agent/funnels",
    "/admin/api/agent/trends?event=AppOpened&metric=count&interval=day&range=30&split=none",
  ];

  afterEach(() => vi.restoreAllMocks());

  it.each(reads)("answers %s to a service token as JSON", async (path) => {
    const response = await admin(path, { token: await signAgent() });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("application/json");
    expect(response.headers.get("cache-control")).toBe("no-store");
    await response.json();
  });

  it("answers the same purchases the panel shows, from D1", async () => {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO purchases VALUES ('tx-1', 'tx-1', 'pair-1', 'com.mikitahimpel.billet.stamps.100',
         100, 'Sandbox', 'refunded', 1, 1, 1000, 1000, 2000)`,
      ),
      env.DB.prepare(
        `INSERT INTO stamp_ledger VALUES ('purchase:tx-1', 'pair-1', 'purchase', 100,
         'com.mikitahimpel.billet.stamps.100', 'tx-1', 1000)`,
      ),
    ]);
    const agent = await (
      await admin("/admin/api/agent/purchases", { token: await signAgent() })
    ).json();
    expect(agent).toEqual(await (await admin("/admin/api/purchases")).json());
    expect(agent).toMatchObject({
      purchases: [{ originalTransactionId: "tx-1", ownerId: "pair-1", flagged: true }],
      ledger: [{ id: "purchase:tx-1", amount: 100 }],
      notifications: [],
    });
  });

  it("counts onboarding answers from D1, and never shows what was typed", async () => {
    await env.DB.batch([
      ...["u1", "u2"].map((id) =>
        env.DB.prepare("INSERT INTO users (id, created_at) VALUES (?, 1)").bind(id),
      ),
      env.DB.prepare(
        `INSERT INTO onboarding_answers VALUES
         ('u1', 'age', '2026-11-04', 'Single', '["age-18-24"]', NULL, NULL, 1000),
         ('u1', 'name', '2026-11-04', 'Text', NULL, NULL, 'Secret Name', 1000),
         ('u1', 'goals', '2026-11-04', 'Multi', '["widgets","raise-pet"]', NULL, NULL, 1000),
         ('u2', 'age', '2026-11-04', 'Skipped', NULL, NULL, NULL, 1000),
         ('u2', 'cat_coat', '2026-11-04', 'Single', '["grey"]', NULL, NULL, 1000)`,
      ),
    ]);
    const response = await admin("/admin/api/agent/onboarding", { token: await signAgent() });
    const text = await response.text();
    expect(text).not.toContain("Secret Name");
    const body = JSON.parse(text);
    expect(body).toEqual(await (await admin("/admin/api/onboarding")).json());
    const step = (id: string) => body.steps.find((s: { id: string }) => s.id === id);
    expect(body.accounts).toBe(2);
    expect(step("age")).toMatchObject({ answered: 1, skipped: 1, skipRate: 0.5 });
    expect(step("name")).toMatchObject({ answered: 1, skipped: 0, options: [] });
    expect(step("goals").options.filter((o: { count: number }) => o.count > 0)).toEqual([
      { id: "raise-pet", label: "Raise a pet together", count: 1 },
      { id: "widgets", label: "Use widgets", count: 1 },
    ]);
    expect(step("cat_coat")).toMatchObject({ native: true, options: [{ id: "grey", count: 1 }] });
  });

  it("answers the same flags the panel shows", async () => {
    const agent = await (
      await admin("/admin/api/agent/flags", { token: await signAgent() })
    ).json();
    expect(agent).toEqual(await (await admin("/admin/api/flags")).json());
  });

  it("looks a pair up by id only, like the panel", async () => {
    const response = await admin("/admin/api/agent/pairs/no-such-pair", {
      token: await signAgent(),
    });
    expect(response.status).toBe(404);
  });

  it("logs each read with the token's common_name", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    await admin("/admin/api/agent/flags", { token: await signAgent() });
    const reads = log.mock.calls
      .map((call) => JSON.parse(String(call[0])) as Record<string, unknown>)
      .filter((line) => line["message"] === "admin agent read");
    expect(reads).toEqual([
      {
        level: "info",
        message: "admin agent read",
        commonName: testAgent,
        pathname: "/admin/api/agent/flags",
      },
    ]);
  });

  it.each([
    ["PUT", "/admin/api/flags/split"],
    ["POST", "/admin/api/experiments/split/kill"],
    ["PUT", "/admin/api/pairs/p1/overrides/split"],
    ["DELETE", "/admin/api/pairs/p1/overrides/split"],
    ["POST", "/admin/api/agent/flags"],
    ["PUT", "/admin/api/agent/flags"],
    ["DELETE", "/admin/api/agent/flags"],
    ["POST", "/admin/api/funnels"],
    ["DELETE", "/admin/api/funnels/00000000-0000-4000-8000-000000000001"],
    ["POST", "/admin/api/agent/funnels"],
  ])(
    "refuses a service token's %s %s with 403, even from the panel's origin",
    async (method, path) => {
      const response = await admin(path, {
        method,
        token: await signAgent(),
        body: JSON.stringify({ expectedVersion: 0, variant: "a" }),
        headers: { "content-type": "application/json", origin, "sec-fetch-site": "same-origin" },
      });
      expect(response.status).toBe(403);
      expect(await response.text()).toBe("Forbidden");
      expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM flag_changes").first("n")).toBe(0);
    },
  );

  it.each(["/admin", "/admin/app.js", "/admin/api/me", "/admin/api/flags", "/admin/api/overview"])(
    "refuses a service token outside the agent API: GET %s",
    async (path) => {
      expect((await admin(path, { token: await signAgent() })).status).toBe(403);
    },
  );

  it("refuses a service token when the Worker has no agent AUD", async () => {
    const response = await admin(
      "/admin/api/agent/flags",
      { token: await signAgent() },
      { ...configured, ACCESS_AGENT_AUD: "" },
    );
    expect(response.status).toBe(403);
  });

  it("refuses a service token for the panel's audience", async () => {
    const response = await admin("/admin/api/agent/flags", {
      token: await signAgent({ aud: [testAccess.audience] }),
    });
    expect(response.status).toBe(403);
  });

  it("refuses the agent API without a token", async () => {
    expect((await admin("/admin/api/agent/flags", { token: null })).status).toBe(403);
  });
});
