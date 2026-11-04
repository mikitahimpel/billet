import { afterEach, describe, expect, it, vi } from "vitest";
import { routeLabel, withRequestSpan } from "../src/observability.ts";

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
    ["GET", "/admin/api/agent/pairs/secret-pair", "GET /admin/*"],
  ])("%s %s is %s", (method, path, label) => {
    expect(routeLabel(method, path)).toBe(label);
  });
});

describe("withRequestSpan", () => {
  it("writes a trace line with the route template, status and request id, and nothing personal", async () => {
    const { lines, restore } = capture();
    const request = new Request(
      "https://billet.test/v1/media/pairs/secret-pair/notes/abc.png?token=s3cret",
      {
        headers: {
          authorization: "Bearer s3cret",
          "cf-connecting-ip": "203.0.113.7",
          "cf-ray": "8d2f0a1b2c3d4e5f-LHR",
        },
      },
    );
    const response = await withRequestSpan(
      request,
      async () => new Response("ok", { status: 200 }),
    );
    restore();

    expect(response.status).toBe(200);
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({
      level: "info",
      message: "trace",
      span: "http.request",
      status: "ok",
      attributes: {
        "http.request.method": "GET",
        "http.route": "GET /v1/media/*",
        "http.response.status_code": 200,
        "request.id": "8d2f0a1b2c3d4e5f-LHR",
      },
    });
    expect(typeof lines[0]?.["ms"]).toBe("number");
    expect(lines[0]?.["traceId"]).toMatch(/^[0-9a-f]{32}$/);
    const text = JSON.stringify(lines);
    for (const secret of ["secret-pair", "abc.png", "s3cret", "203.0.113.7"]) {
      expect(text).not.toContain(secret);
    }
  });

  it("logs a thrown error once with its class and request id only, and answers 500", async () => {
    const { lines, restore } = capture();
    const request = new Request("https://billet.test/v1/notes", {
      headers: { "cf-ray": "8d2f0a1b2c3d4e5f-LHR" },
    });
    const response = await withRequestSpan(request, async () => {
      throw new TypeError("note body 4242 and token s3cret");
    });
    restore();

    expect(response.status).toBe(500);
    const crash = lines.find((line) => line["message"] === "request crashed");
    const trace = lines.find((line) => line["message"] === "trace");
    expect(crash).toMatchObject({ level: "error", requestId: "8d2f0a1b2c3d4e5f-LHR" });
    expect(JSON.stringify(crash?.["cause"])).toContain("TypeError");
    expect(crash?.["traceId"]).toBe(trace?.["traceId"]);
    expect(trace).toMatchObject({
      status: "error",
      attributes: { "http.route": "GET /v1/notes", "http.response.status_code": 500 },
    });
    expect(JSON.stringify(lines)).not.toContain("s3cret");
    expect(JSON.stringify(lines)).not.toContain("4242");
  });
});
