import { describe, expect, it } from "vitest";
import { buildReport } from "@billet/backend-metrics/funnel";
import { makeSeed, seedCleanupSql, seedSql } from "../src/seed-data.ts";

const today = "2026-11-04";

describe("makeSeed", () => {
  const seed = makeSeed({ today });

  it("is the same for the same seed and day", () => {
    expect(makeSeed({ today })).toEqual(seed);
    expect(makeSeed({ today, seed: 7 })).not.toEqual(seed);
  });

  it("makes about 170 pairs over ten weeks, none after today, every id marked as seed", () => {
    const pairs = new Set(seed.members.map(({ pairId }) => pairId));
    expect(pairs.size).toBeGreaterThan(150);
    expect(seed.events.every(({ day }) => day <= today && day >= "2026-08-26")).toBe(true);
    expect(seed.users.every(({ id }) => id.startsWith("seed-"))).toBe(true);
    expect([...pairs].every((id) => id.startsWith("seed-"))).toBe(true);
  });

  it("looks like an app people drift away from", () => {
    const report = buildReport(seed.events, seed.flags, today);
    const [d1, d7, d30] = report.days.map(({ bothActive }) => bothActive.share ?? 0);
    expect(d1).toBeGreaterThan(d7 ?? 0);
    expect(d7).toBeGreaterThan(d30 ?? 0);
    expect(d30).toBeGreaterThan(0.03);
  });

  it("leaves the build off what the server records, as the real write path does", () => {
    for (const event of seed.events) {
      const server = ["InviteCreated", "PairClaimed", "NoteSent"].includes(event.name);
      expect(event.appVersion === null).toBe(server);
    }
  });

  it("writes SQL that starts by removing earlier seed rows", () => {
    const sql = seedSql(seed, { eventBuild: true });
    expect(sql.startsWith(seedCleanupSql.join("\n"))).toBe(true);
    expect(sql).toContain(
      "INSERT INTO pair_events (pair_id, user_id, name, day, count, first_at, last_at, app_version, os)",
    );
  });
});
