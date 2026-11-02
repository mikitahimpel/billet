import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { groupOf, limitRequest, limits, windowMillis } from "../src/rate-limit.ts";
import { resetDirectory } from "./directory-migrations.ts";

const post = (path: string, ip = "203.0.113.7") =>
  new Request(`https://billet.test${path}`, {
    method: "POST",
    headers: { "cf-connecting-ip": ip },
  });

const spend = async (path: string, times: number, ip?: string, now?: number) => {
  let last: Response | undefined;
  for (let i = 0; i < times; i++) last = await limitRequest(post(path, ip), env.DB, now);
  return last;
};

beforeEach(async () => {
  await resetDirectory();
});

describe("rate limit groups", () => {
  it.each([
    ["/v1/auth/challenge", "auth"],
    ["/v1/auth/apple", "auth"],
    ["/v1/invites", "pairing"],
    ["/v1/invites/claim", "pairing"],
    ["/v1/pair", "pairing"],
    ["/v1/media", "media"],
    ["/v1/media/pairs/p/notes/n.png", "media"],
    ["/v1/notes", undefined],
    ["/", undefined],
  ])("%s is %s", (path, group) => {
    expect(groupOf(path)).toBe(group);
  });
});

describe("limitRequest", () => {
  it("lets a group's limit through and answers 429 after it", async () => {
    expect(await spend("/v1/auth/challenge", limits.auth)).toBeUndefined();
    const refused = await spend("/v1/auth/challenge", 1);
    expect(refused?.status).toBe(429);
    expect(Number(refused?.headers.get("retry-after"))).toBeGreaterThan(0);
    expect(await refused?.json()).toEqual({ _tag: "Unavailable" });
  });

  it("counts each group and each caller on its own", async () => {
    await spend("/v1/auth/challenge", limits.auth + 1);
    expect(await spend("/v1/invites", 1)).toBeUndefined();
    expect(await spend("/v1/auth/challenge", 1, "198.51.100.9")).toBeUndefined();
  });

  it("starts counting again in the next window", async () => {
    const now = 1_700_000_000_000;
    expect((await spend("/v1/auth/challenge", limits.auth + 1, undefined, now))?.status).toBe(429);
    expect(await spend("/v1/auth/challenge", 1, undefined, now + windowMillis)).toBeUndefined();
  });

  it("does not store the caller's address", async () => {
    await spend("/v1/auth/challenge", 1, "203.0.113.7");
    const rows = await env.DB.prepare("SELECT bucket FROM rate_limits").all<{ bucket: string }>();
    expect(rows.results).toHaveLength(1);
    expect(rows.results[0]?.bucket).toMatch(/^[0-9a-f]{64}$/);
  });

  it("lets requests through when the counter cannot be read", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const broken = {
      prepare: () => ({ bind: () => ({}) }),
      batch: () => Promise.reject(new Error("203.0.113.7 secret")),
    };
    expect(
      await limitRequest(post("/v1/auth/challenge"), broken as unknown as D1Database),
    ).toBeUndefined();
    expect(warn).toHaveBeenCalledWith("rate limit counter unavailable");
    warn.mockRestore();
  });
});
