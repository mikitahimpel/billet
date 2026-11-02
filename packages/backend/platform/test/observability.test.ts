import { afterEach, describe, expect, it, vi } from "vitest";
import { routeLabel, withRequestLog } from "../src/observability.ts";

const capture = () => {
  const lines: Array<Record<string, unknown>> = [];
  const record = (line: string) => {
    lines.push(JSON.parse(line));
  };
  const spies = (["log", "warn", "error"] as const).map((level) =>
    vi.spyOn(console, level).mockImplementation(record),
  );
  return { lines, restore: () => spies.forEach((spy) => spy.mockRestore()) };
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe("routeLabel", () => {
  it.each([
    ["POST", "/v1/notes", "POST /v1/notes"],
    ["GET", "/v1/notes", "GET /v1/notes"],
    ["GET", "/v1/media/pairs/secret-pair/notes/abc.png", "GET /v1/media/*"],
    ["GET", "/v1/socket", "GET /v1/socket"],
    ["DELETE", "/v1/notes", "unmatched"],
    ["GET", "/v1/anything/else", "unmatched"],
  ])("%s %s is %s", (method, path, label) => {
    expect(routeLabel(method, path)).toBe(label);
  });
});

describe("withRequestLog", () => {
  it("logs the route template, status and duration, and nothing from the request", async () => {
    const { lines, restore } = capture();
    const request = new Request(
      "https://billet.test/v1/media/pairs/secret-pair/notes/abc.png?token=s3cret",
      { headers: { authorization: "Bearer s3cret", "cf-connecting-ip": "203.0.113.7" } },
    );
    const response = await withRequestLog(request, async () => new Response("ok", { status: 200 }));
    restore();

    expect(response.status).toBe(200);
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({ event: "request", route: "GET /v1/media/*", status: 200 });
    expect(typeof lines[0]?.["ms"]).toBe("number");
    const text = JSON.stringify(lines);
    for (const secret of ["secret-pair", "abc.png", "s3cret", "203.0.113.7"]) {
      expect(text).not.toContain(secret);
    }
  });

  it("logs a thrown error as a crash with its class only, and answers 500", async () => {
    const { lines, restore } = capture();
    const response = await withRequestLog(new Request("https://billet.test/v1/notes"), async () => {
      throw new TypeError("note body 4242 and token s3cret");
    });
    restore();

    expect(response.status).toBe(500);
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({ event: "crash", route: "GET /v1/notes", error: "TypeError" });
    expect(JSON.stringify(lines)).not.toContain("s3cret");
  });
});
