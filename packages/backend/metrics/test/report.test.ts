import { describe, expect, it, vi } from "vitest";
import { buildReport } from "../src/funnel.ts";
import { formatReport } from "../src/report-format.ts";
import { runReport } from "../src/report-cli.ts";
import { readRows, statements } from "../src/report-source.ts";

const source = { accountId: "acct", databaseId: "db-1", apiToken: "token-value-123" };

const reply = (results: ReadonlyArray<unknown>) =>
  new Response(JSON.stringify({ success: true, result: [{ results }] }), { status: 200 });

describe("formatReport", () => {
  it("prints an empty report without dividing by zero", () => {
    const text = formatReport(buildReport([], [], "2026-11-20"));
    expect(text).toContain("pairs formed                     0");
    expect(text).not.toMatch(/NaN|Infinity|undefined/);
  });

  it("states what is not stored, and marks the north star", () => {
    const text = formatReport(buildReport([], [], "2026-11-20"));
    expect(text).toContain("No note, image or text is stored or read.");
    expect(text).toContain("<- north star");
  });

  it("prints intervals next to every share", () => {
    const events = [
      {
        pairId: "p1",
        userId: "a",
        name: "PairClaimed" as const,
        day: "2026-11-01",
        count: 1,
        firstAt: 1,
      },
      {
        pairId: "p1",
        userId: "b",
        name: "PairClaimed" as const,
        day: "2026-11-01",
        count: 1,
        firstAt: 1,
      },
    ];
    expect(formatReport(buildReport(events, [], "2026-11-20"))).toMatch(
      /0\/1 = 0% \(95% 0% to \d+%\)/,
    );
  });
});

describe("report source", () => {
  it("sends only SELECT statements", () => {
    for (const sql of Object.values(statements)) {
      expect(sql.trimStart().toUpperCase().startsWith("SELECT")).toBe(true);
      expect(sql).not.toMatch(/;|\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|REPLACE|PRAGMA)\b/i);
    }
  });

  it("reads through the Cloudflare API with the bearer token, and nothing is logged", async () => {
    const fetcher = vi.fn<typeof fetch>(async (_url, init) => {
      const body = JSON.parse(String(init?.body)) as { sql: string };
      return reply(
        body.sql.includes("pair_events")
          ? [
              {
                pair_id: "p1",
                user_id: "a",
                name: "NoteSent",
                day: "2026-11-01",
                count: 2,
                first_at: 5,
              },
            ]
          : [{ pair_id: "p1", experiment_key: "home-direction", variant: "window-seat" }],
      );
    });
    const rows = await readRows(source, fetcher);
    expect(rows.events).toEqual([
      { pairId: "p1", userId: "a", name: "NoteSent", day: "2026-11-01", count: 2, firstAt: 5 },
    ]);
    expect(rows.flags).toEqual([
      { pairId: "p1", experimentKey: "home-direction", variant: "window-seat" },
    ]);
    const [url, init] = fetcher.mock.calls[0] ?? [];
    expect(String(url)).toBe(
      "https://api.cloudflare.com/client/v4/accounts/acct/d1/database/db-1/query",
    );
    expect(new Headers(init?.headers).get("authorization")).toBe("Bearer token-value-123");
  });

  it("pages through more rows than one page holds", async () => {
    const full = Array.from({ length: 5_000 }, (_, i) => ({
      pair_id: "p1",
      user_id: `u${i}`,
      name: "AppOpened",
      day: "2026-11-01",
      count: 1,
      first_at: 1,
    }));
    let calls = 0;
    const fetcher = vi.fn<typeof fetch>(async (_url, init) => {
      const body = JSON.parse(String(init?.body)) as { sql: string; params: [number] };
      if (!body.sql.includes("pair_events")) return reply([]);
      calls += 1;
      return reply(body.params[0] === 0 ? full : [full[0]]);
    });
    const rows = await readRows(source, fetcher);
    expect(rows.events).toHaveLength(5_001);
    expect(calls).toBe(2);
  });

  it("fails with the status only, never quoting the response or the token", async () => {
    const fetcher = vi.fn<typeof fetch>(
      async () => new Response("token-value-123 is not allowed", { status: 403 }),
    );
    const error = await readRows(source, fetcher).catch((caught: unknown) => caught);
    expect(String(error)).toBe("Error: D1 query failed with status 403");
    expect(String(error)).not.toContain("token-value-123");
  });

  it("refuses a row with an event name it does not know", async () => {
    const fetcher = vi.fn<typeof fetch>(async () =>
      reply([
        { pair_id: "p1", user_id: "a", name: "NoteBody", day: "2026-11-01", count: 1, first_at: 1 },
      ]),
    );
    await expect(readRows(source, fetcher)).rejects.toThrow();
  });
});

describe("runReport", () => {
  const env = {
    CLOUDFLARE_ACCOUNT_ID: "acct",
    CLOUDFLARE_API_TOKEN: "token-value-123",
    BILLET_D1_DATABASE_ID: "db-1",
  };
  const empty = vi.fn<typeof fetch>(async () => reply([]));

  it("names the missing variables, and prints none of the present ones", async () => {
    const result = await runReport({ CLOUDFLARE_API_TOKEN: "token-value-123" }, empty);
    expect(result.ok).toBe(false);
    expect(result.text).toContain("CLOUDFLARE_ACCOUNT_ID, BILLET_D1_DATABASE_ID");
    expect(result.text).not.toContain("token-value-123");
    expect(empty).not.toHaveBeenCalled();
  });

  it("prints the report for the UTC day it is run", async () => {
    const result = await runReport(env, empty, Date.UTC(2026, 10, 20, 23, 59));
    expect(result.ok).toBe(true);
    expect(result.text).toContain("up to 2026-11-20 (UTC days)");
  });

  it("reports a failed read without the token", async () => {
    const result = await runReport(
      env,
      vi.fn<typeof fetch>(async () => new Response("denied token-value-123", { status: 401 })),
    );
    expect(result.ok).toBe(false);
    expect(result.text).toBe("D1 query failed with status 401\n");
  });
});
