import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { Effect, Schema } from "effect";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CoinEntryId, type CoinEntry } from "@billet/contracts-domain/coins";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { PairRoom } from "../src/pair-room-durable-object.ts";
import { openDirectoryDatabase } from "../src/directory-database.ts";
import { recordEconomy } from "../src/economy-sink-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const { PAIR_ROOM } = env as unknown as { PAIR_ROOM: DurableObjectNamespace<PairRoom> };

const pairId = Schema.decodeSync(PairId)("pair-economy");
const entryId = Schema.decodeSync(CoinEntryId);
const at = Date.UTC(2026, 10, 13, 12, 0, 0);
const day = "2026-11-13";

const entry = (id: string, kind: CoinEntry["kind"], amount: number, when = at): CoinEntry => ({
  id: entryId(id),
  kind,
  amount,
  ref: "x",
  at: when,
});

const wallet = (over: Record<string, unknown> = {}) => ({
  balance: 0,
  care: 0,
  notes: 0,
  games: 0,
  lists: 0,
  ...over,
});

const record = (observation: Parameters<typeof recordEconomy>[1]) =>
  Effect.runPromise(
    Effect.scoped(
      openDirectoryDatabase(env.DB).pipe(Effect.flatMap((db) => recordEconomy(db, observation))),
    ),
  );

const days = async () =>
  (
    await env.DB.prepare(
      "SELECT source, credited, debited, entries FROM economy_days WHERE day = ? ORDER BY source",
    )
      .bind(day)
      .all<{ source: string; credited: number; debited: number; entries: number }>()
  ).results;

const pairDay = () =>
  env.DB.prepare("SELECT * FROM economy_pair_days WHERE pair_id = ? AND day = ?")
    .bind(pairId, day)
    .first<Record<string, number | string>>();

beforeEach(async () => {
  await resetDirectory();
});

describe("recordEconomy", () => {
  it("adds each change to the day's source totals and the pair's day", async () => {
    await record({
      pairId,
      at,
      entries: [entry("earn:a", "earn", 4)],
      before: wallet({ balance: 6, day: "2026-11-13", care: 6 }),
      after: wallet({ balance: 10, day: "2026-11-13", care: 10 }),
    });
    await record({
      pairId,
      at: at + 1000,
      entries: [entry("spend:b", "spend", -60, at + 1000)],
      before: wallet({ balance: 70, day: "2026-11-13", care: 10 }),
      after: wallet({ balance: 10, day: "2026-11-13", care: 10 }),
    });
    await record({
      pairId,
      at: at + 2000,
      entries: [entry("earn:c", "earn", 5, at + 2000)],
      before: wallet({ balance: 10, day: "2026-11-13", care: 10 }),
      after: wallet({ balance: 15, day: "2026-11-13", care: 10, notes: 5 }),
    });
    expect(await days()).toEqual([
      { source: "earn.care", credited: 4, debited: 0, entries: 1 },
      { source: "earn.notes", credited: 5, debited: 0, entries: 1 },
      { source: "spend", credited: 0, debited: 60, entries: 1 },
    ]);
    expect(await pairDay()).toMatchObject({
      earned: 9,
      balance: 15,
      last_at: at + 2000,
      capped_care: 1,
      capped_notes: 0,
    });
  });

  it("keeps the balance after the latest change when writes land out of order", async () => {
    const change = (when: number, balance: number) => ({
      pairId,
      at: when,
      entries: [entry(`gift:${when}`, "gift", 1, when)],
      before: wallet(),
      after: wallet({ balance }),
    });
    await record(change(at + 5000, 50));
    await record(change(at + 1000, 10));
    expect(await pairDay()).toMatchObject({ balance: 50, last_at: at + 5000 });
  });

  it("records a refund that leaves the balance negative", async () => {
    await record({
      pairId,
      at,
      entries: [entry("refund:1", "refund", -550)],
      before: wallet({ balance: 30 }),
      after: wallet({ balance: -520 }),
    });
    expect(await days()).toEqual([{ source: "refund", credited: 0, debited: 550, entries: 1 }]);
    expect(await pairDay()).toMatchObject({ balance: -520, earned: 0 });
  });
});

describe("the pair room", () => {
  it("counts a bought pack once its commit lands", async () => {
    const room = PAIR_ROOM.get(PAIR_ROOM.newUniqueId());
    const alice = Schema.decodeSync(UserId)("user-alice");
    const bob = Schema.decodeSync(UserId)("user-bob");
    // The first D1 call of a fresh object stalls the test harness unless the object is already awake.
    await runInDurableObject(room, async () => {
      await env.DB.prepare("SELECT 1").first();
    });
    await room.open(pairId, [alice, bob]);
    await room.creditPurchase({
      kind: "purchase",
      id: entryId("purchase:2000"),
      ref: "pack",
      coins: 100,
    });
    await vi.waitFor(async () => expect(await purchased()).toBe(100), { timeout: 4000 });
  });
});

const purchased = async () =>
  (
    await env.DB.prepare(
      "SELECT coalesce(sum(credited), 0) AS n FROM economy_days WHERE source = 'purchase'",
    ).first<{
      n: number;
    }>()
  )?.n ?? 0;
