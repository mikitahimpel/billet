import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { agentApi } from "@billet/backend-admin/admin-routes";

const script = resolve(process.cwd(), "../../../scripts/admin-read.sh");

// A stand-in `curl` first on PATH: it records its arguments and answers 200, so no request leaves.
const run = (route: string) => {
  const bin = mkdtempSync(join(tmpdir(), "admin-read-"));
  const log = join(bin, "args");
  writeFileSync(
    join(bin, "curl"),
    `#!/bin/sh\ncat >/dev/null\nprintf '%s\\n' "$@" >"${log}"\nprintf 200\n`,
  );
  chmodSync(join(bin, "curl"), 0o755);
  const result = spawnSync("sh", [script, route], {
    encoding: "utf8",
    env: {
      PATH: `${bin}:${process.env["PATH"] ?? ""}`,
      BILLET_ADMIN_HOST: "admin.example",
      CF_ACCESS_CLIENT_ID: "id",
      CF_ACCESS_CLIENT_SECRET: "secret",
    },
  });
  const args = result.status === 0 ? readFileSync(log, "utf8").split("\n") : [];
  return { status: result.status, args };
};

const accepted = [
  "overview",
  "overview?days=7",
  "retention",
  "retention?variant=rooms=room-only&version=1.2.0%2B14",
  "funnel?steps=PairClaimed,NoteSent&window=7d&unit=pair&range=90",
  "funnels",
  "trends?event=AppOpened&metric=pairs&interval=week&range=90&split=none",
  "features",
  "features?split=rooms",
  "experiments",
  "flags",
  "flag-history?key=rooms&limit=10",
  "onboarding",
  "shop-items",
  "shop-history?limit=50",
  "status",
  "status-history?limit=5",
  "purchases?limit=100",
  "economy?range=30&hold=14",
  "pairs/pair_123",
];

const refused = [
  "overview?days=8",
  "funnel",
  "trends",
  "funnels/abc",
  "experiments/rooms/start",
  "flags/rooms",
  "pairs/a/overrides/rooms",
  "retention?variant=a b",
  "features?split=../flags",
  "features#x",
  "../api/flags",
  "review/wipe",
  "reports",
];

describe("scripts/admin-read.sh", () => {
  it.each(accepted)("reads %s with a GET under the agent prefix", (route) => {
    const { status, args } = run(route);
    expect(status).toBe(0);
    expect(args).toContain(`https://admin.example/admin/api/agent/${route}`);
    expect(
      args.some((arg: string) => /^(-X|--request|-d|--data.*|-F|--form.*|-T)$/.test(arg)),
    ).toBe(false);
  });

  it.each(refused)("refuses %s before any request", (route) => {
    expect(run(route).status).toBe(2);
  });

  it("names a route the Worker serves to agents", () => {
    const served = Object.values(agentApi).map((path) => path.split("/")[4]);
    for (const route of accepted) {
      expect(served).toContain(route.split(/[?/]/)[0]);
    }
  });
});
