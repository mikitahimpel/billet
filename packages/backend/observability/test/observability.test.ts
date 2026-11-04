import { Data, Effect, Redacted } from "effect";
import { describe, expect, it } from "vitest";
import type { LogSink, SinkLevel } from "../src/json-logger.ts";
import { observabilityLayer } from "../src/observability-layer.ts";
import { annotateRefs, opaqueRef } from "../src/opaque-ref.ts";
import { spanMethods } from "../src/span-methods.ts";

const fakeToken = "tok_live_9f8e7d6c5b4a39281706f5e4d3c2b1a0ZZ";
const fakeJwt = "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.c2lnbmF0dXJlLXRoYXQtaXMtbG9uZw";
const fakeEmail = "someone@example.com";

const capture = () => {
  const lines: Array<{ readonly level: SinkLevel; readonly json: Record<string, unknown> }> = [];
  const raw: Array<string> = [];
  const sink: LogSink = (level, line) => {
    raw.push(line);
    lines.push({ level, json: JSON.parse(line) as Record<string, unknown> });
  };
  return { lines, raw, layer: observabilityLayer(sink) };
};

class SignInFailed extends Data.TaggedError("SignInFailed")<{
  readonly reason: string;
  readonly token: string;
}> {}

describe("jsonLogger", () => {
  it("never prints a Redacted value, a token, a JWT or an email", async () => {
    const { raw, lines, layer } = capture();
    await Effect.runPromise(
      Effect.gen(function* () {
        yield* Effect.logInfo("signed in", Redacted.make(fakeToken));
        yield* Effect.logInfo("headers", { authorization: `Bearer ${fakeToken}`, route: "x" });
        yield* Effect.logWarning("raw values", fakeToken, `Bearer ${fakeJwt}`, fakeEmail);
        yield* Effect.logError("nested", { a: { b: { sessionToken: fakeToken, ok: 1 } } });
        yield* Effect.logError("failed", new SignInFailed({ reason: "expired", token: fakeToken }));
        yield* Effect.logError("thrown", new Error(`bad token ${fakeToken}`));
        yield* Effect.fail(new SignInFailed({ reason: "x", token: fakeToken })).pipe(
          Effect.tapCause((cause) => Effect.logError("with cause", cause)),
          Effect.ignore,
        );
      }).pipe(
        Effect.annotateLogs({ sessionToken: Redacted.make(fakeToken), email: fakeEmail }),
        Effect.provide(layer),
      ),
    );

    const output = raw.join("\n");
    expect(output).not.toContain(fakeToken);
    expect(output).not.toContain(fakeJwt);
    expect(output).not.toContain(fakeEmail);
    expect(output).not.toContain("bad token");
    // Fixed labels survive: the logs stay useful.
    expect(lines.map((line) => line.json["message"])).toContain("signed in");
    const failed = lines.find((line) => line.json["message"] === "failed");
    expect(failed?.level).toBe("error");
    expect(failed?.json["data"]).toMatchObject({ _tag: "SignInFailed", reason: "expired" });
  });

  it("writes the trace and span ids and the annotations of the line", async () => {
    const { lines, layer } = capture();
    await Effect.runPromise(
      Effect.logInfo("inside").pipe(
        Effect.withSpan("Room.open"),
        Effect.annotateLogs({ requestId: "8d2f0a1b2c3d4e5f-LHR" }),
        Effect.provide(layer),
      ),
    );
    const inside = lines.find((line) => line.json["message"] === "inside")?.json;
    const trace = lines.find((line) => line.json["message"] === "trace")?.json;
    expect(inside).toMatchObject({
      level: "info",
      span: "Room.open",
      requestId: "8d2f0a1b2c3d4e5f-LHR",
    });
    expect(inside?.["traceId"]).toBe(trace?.["traceId"]);
    expect(inside?.["spanId"]).toBe(trace?.["spanId"]);
  });
});

describe("traceLogTracer", () => {
  const find = Effect.fn("Repository.find")(function* (id: string) {
    yield* Effect.annotateCurrentSpan("rows", 1);
    return id.length;
  });
  const failing = Effect.fn("Service.fails")(function* () {
    return yield* new SignInFailed({ reason: "expired", token: fakeToken });
  });
  const handle = Effect.fn("Service.handle")(function* (id: string) {
    yield* annotateRefs({ user: id });
    yield* Effect.ignore(failing());
    return yield* find(id);
  });

  it("writes one trace line per root span with its children", async () => {
    const { lines, layer } = capture();
    await Effect.runPromise(
      handle("user-1").pipe(
        Effect.withSpan("http.request", { attributes: { "http.route": "POST /v1/notes" } }),
        Effect.provide(layer),
      ),
    );
    const traces = lines.filter((line) => line.json["message"] === "trace");
    expect(traces).toHaveLength(1);
    const trace = traces[0]!.json;
    expect(trace).toMatchObject({
      span: "http.request",
      status: "ok",
      attributes: { "http.route": "POST /v1/notes", "user.ref": opaqueRef("user-1") },
    });
    const spans = trace["spans"] as ReadonlyArray<Record<string, unknown>>;
    expect(spans.map((span) => span["name"])).toEqual([
      "Service.fails",
      "Repository.find",
      "Service.handle",
    ]);
    const handleSpan = spans.find((span) => span["name"] === "Service.handle")!;
    expect(handleSpan["parentId"]).toBe(trace["spanId"]);
    expect(handleSpan["attributes"]).toEqual({ "user.ref": opaqueRef("user-1") });
    expect(spans.find((span) => span["name"] === "Service.fails")).toMatchObject({
      status: "error",
      error: "SignInFailed",
    });
    expect(JSON.stringify(trace)).not.toContain("user-1");
  });
});

describe("opaqueRef", () => {
  it("is stable, 16 hex digits, and not the id", () => {
    expect(opaqueRef("pair-abc")).toBe(opaqueRef("pair-abc"));
    expect(opaqueRef("pair-abc")).not.toBe(opaqueRef("pair-abd"));
    expect(opaqueRef("pair-abc")).toMatch(/^[0-9a-f]{16}$/);
  });
});

describe("spanMethods", () => {
  it("names a span after the service and member, for methods and Effect members", async () => {
    const { lines, layer } = capture();
    const repo = spanMethods("NotesRepository", {
      find: (id: string) => Effect.succeed(id.length),
      all: Effect.succeed([1, 2]),
      label: "notes",
    });
    expect(repo.label).toBe("notes");
    await Effect.runPromise(
      Effect.all([repo.find("abc"), repo.all]).pipe(
        Effect.withSpan("http.request"),
        Effect.provide(layer),
      ),
    );
    const trace = lines.find((line) => line.json["message"] === "trace")!.json;
    const names = (trace["spans"] as ReadonlyArray<Record<string, unknown>>).map((s) => s["name"]);
    expect(names).toEqual(["NotesRepository.find", "NotesRepository.all"]);
  });
});
