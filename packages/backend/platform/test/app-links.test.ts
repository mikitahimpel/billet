import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { respondApi } from "../src/api-fetch.ts";
import { codeOfInviteLink, respondAppLink } from "../src/app-links.ts";
import { limits } from "../src/rate-limit.ts";
import { resetDirectory } from "./directory-migrations.ts";
import { testExperiments } from "./test-experiments.ts";

describe("Universal Links", () => {
  it("serves the association file for invite links, to both apps", async () => {
    const response = respondAppLink("/.well-known/apple-app-site-association");
    expect(response?.headers.get("content-type")).toBe("application/json");
    expect(await response?.json()).toEqual({
      applinks: {
        details: [
          {
            appIDs: ["2666YPBJTB.com.ourio.app", "2666YPBJTB.com.mikitahimpel.billet"],
            components: [{ "/": "/i/*" }],
          },
        ],
      },
    });
  });

  it.each([
    ["/i/K7QM4R2XHP", "K7QM4R2XHP"],
    ["/i/k7qm4r2xhp", "K7QM4R2XHP"],
    ["/i/K7QM4-R2XHP", "K7QM4R2XHP"],
    ["/i/K7QM4R2XH0", undefined],
    ["/i/K7QM4", undefined],
    ["/i/K7QM4--R2XHP", undefined],
    ["/i/K7QM4R2XHPX", undefined],
    ["/i/", undefined],
  ])("reads %s as %s", (path, code) => {
    expect(codeOfInviteLink(path)).toBe(code);
  });

  it("shows a well-formed code grouped, with a copy button, and a broken one without a code", async () => {
    const page = await respondAppLink("/i/k7qm4-r2xhp")?.text();
    expect(page).toContain("<code>K7QM4 R2XHP</code>");
    expect(page).toContain('writeText("K7QM4R2XHP")');

    const broken = respondAppLink("/i/<script>");
    expect(broken?.status).toBe(200);
    const text = await broken?.text();
    expect(text).toContain("This invite link is broken");
    expect(text).not.toContain("<code>");
    expect(text).not.toContain("<script>");
  });

  it("keeps the page out of caches and search", () => {
    const headers = respondAppLink("/i/K7QM4R2XHP")?.headers;
    expect(headers?.get("cache-control")).toBe("no-store");
    expect(headers?.get("x-robots-tag")).toBe("noindex");
    expect(headers?.get("content-type")).toBe("text/html; charset=utf-8");
    expect(headers?.get("content-security-policy")).toContain("default-src 'none'");
  });

  it("leaves other paths alone", () => {
    expect(respondAppLink("/i/K7QM4R2XHP/more")).toBeUndefined();
    expect(respondAppLink("/")).toBeUndefined();
  });
});

describe("an invite link through the Worker", () => {
  const code = "K7QM4R2XHP";
  const lines: Array<string> = [];

  beforeEach(async () => {
    await resetDirectory();
    lines.length = 0;
    for (const level of ["log", "info", "warn", "error", "debug"] as const) {
      vi.spyOn(console, level).mockImplementation((...args: unknown[]) => {
        lines.push(
          args.map((arg) => (typeof arg === "string" ? arg : JSON.stringify(arg))).join(" "),
        );
      });
    }
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  // Records every statement the Worker sends to the directory.
  const watched = () => {
    const statements: Array<string> = [];
    const db = new Proxy(env.DB, {
      get: (target, key) =>
        key === "prepare"
          ? (sql: string) => {
              statements.push(sql);
              return target.prepare(sql);
            }
          : Reflect.get(target, key, target),
    });
    return { statements, env: { ...env, DB: db } };
  };

  const open = async (workerEnv: typeof env, ip = "203.0.113.7") => {
    const ctx = createExecutionContext();
    const response = await respondApi(
      new Request(`https://billet.test/i/${code}`, { headers: { "cf-connecting-ip": ip } }),
      workerEnv,
      ctx,
      testExperiments,
    );
    await waitOnExecutionContext(ctx);
    return response;
  };

  it("answers with the page, touches no invite, and logs nothing with the code", async () => {
    const { statements, env: workerEnv } = watched();
    const response = await open(workerEnv);
    expect(response.status).toBe(200);
    expect(await response.text()).toContain("K7QM4 R2XHP");
    expect(statements.length).toBeGreaterThan(0);
    expect(statements.every((sql) => sql.includes("rate_limits"))).toBe(true);
    expect(lines.filter((line) => line.includes(code))).toEqual([]);
  });

  it("is rate limited per caller", async () => {
    for (let i = 0; i < limits.links; i++) expect((await open(env)).status).toBe(200);
    const refused = await open(env);
    expect(refused.status).toBe(429);
    expect(refused.headers.get("content-type")).toBe("text/plain; charset=utf-8");
    expect((await open(env, "198.51.100.9")).status).toBe(200);
  });
});
