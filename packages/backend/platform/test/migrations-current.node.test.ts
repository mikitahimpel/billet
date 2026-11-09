import { execFileSync } from "node:child_process";
import { describe, expect, it } from "vitest";

// A schema change without a committed migration would otherwise be generated during the deploy and
// applied without review (D1), or never reach the Worker bundle (Durable Object).
const plan = (schema: string, out: string) =>
  JSON.parse(
    execFileSync(
      "pnpm",
      [
        "exec",
        "drizzle-kit",
        "generate",
        "--dialect",
        "sqlite",
        "--schema",
        schema,
        "--out",
        out,
        "--explain",
        "--output",
        "json",
      ],
      { encoding: "utf8" },
    ),
  );

// drizzle-kit is a child process that replays every migration, so it takes seconds and grows with
// each migration: the default 5 s timeout is too short.
const planTimeout = 30_000;

describe("committed migrations", () => {
  it.each([
    ["./src/directory-schema.ts", "./migrations/directory"],
    ["./src/room-schema.ts", "./migrations/room"],
  ])(
    "match %s",
    (schema, out) => {
      expect(plan(schema, out)).toEqual({ status: "no_changes", dialect: "sqlite" });
    },
    planTimeout,
  );
});
