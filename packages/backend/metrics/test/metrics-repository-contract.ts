import { Effect, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import type { MetricsRepository } from "../src/metrics-repository.ts";

const user = Schema.decodeSync(UserId);
const ana = user("user-a");
const ben = user("user-b");

const day1 = Date.UTC(2026, 10, 2, 9, 0, 0);
const day1Later = Date.UTC(2026, 10, 2, 23, 59, 59);
const day2 = Date.UTC(2026, 10, 3, 0, 0, 0);

/**
 * The behaviour every `MetricsRepository` must have. Run it against each implementation, so the
 * in-memory fake can't drift from the real one. `make` must return an empty repository.
 */
export const describeMetricsRepositoryContract = (
  name: string,
  make: () => Promise<MetricsRepository["Service"]>,
) =>
  describe(`${name} (MetricsRepository contract)`, () => {
    it("starts a day's count at one, remembering when it began", async () => {
      const repository = await make();
      await Effect.runPromise(
        repository.record({ pairId: "p1", userId: ana, name: "NoteSent", at: day1 }),
      );
      expect(await Effect.runPromise(repository.all)).toEqual([
        {
          pairId: "p1",
          userId: ana,
          name: "NoteSent",
          day: "2026-11-02",
          count: 1,
          firstAt: day1,
          lastAt: day1,
          appVersion: null,
          os: null,
        },
      ]);
    });

    it("keeps the build and system of the day's latest report, and keeps them when one has none", async () => {
      const repository = await make();
      const opened = (at: number, client?: { appVersion: string; os: string }) =>
        Effect.runPromise(
          repository.record({ pairId: "p1", userId: ana, name: "AppOpened", at, client }),
        );
      await opened(day1, { appVersion: "1.1.0+12", os: "iOS 26.0" });
      await opened(day1 + 1_000, { appVersion: "1.2.0+14", os: "iOS 26.1" });
      await opened(day1 + 2_000);
      expect(await Effect.runPromise(repository.all)).toMatchObject([
        { count: 3, appVersion: "1.2.0+14", os: "iOS 26.1" },
      ]);
    });

    it("adds to the count within a UTC day and keeps the first moment", async () => {
      const repository = await make();
      for (const at of [day1, day1Later, day1]) {
        await Effect.runPromise(
          repository.record({ pairId: "p1", userId: ana, name: "NoteSent", at }),
        );
      }
      const [row] = await Effect.runPromise(repository.all);
      expect(row).toMatchObject({ count: 3, firstAt: day1, lastAt: day1Later });
    });

    it("starts a new row on the next UTC day", async () => {
      const repository = await make();
      await Effect.runPromise(
        repository.record({ pairId: "p1", userId: ana, name: "NoteSent", at: day1Later }),
      );
      await Effect.runPromise(
        repository.record({ pairId: "p1", userId: ana, name: "NoteSent", at: day2 }),
      );
      expect((await Effect.runPromise(repository.all)).map(({ day }) => day)).toEqual([
        "2026-11-02",
        "2026-11-03",
      ]);
    });

    it("keeps people, pairs and names apart, and an empty pair for what happens before pairing", async () => {
      const repository = await make();
      await Effect.runPromise(
        Effect.all([
          repository.record({ pairId: "p1", userId: ana, name: "NoteSent", at: day1 }),
          repository.record({ pairId: "p1", userId: ben, name: "NoteSent", at: day1 }),
          repository.record({ pairId: "p1", userId: ana, name: "AppOpened", at: day1 }),
          repository.record({ pairId: "", userId: ana, name: "InviteCreated", at: day1 }),
        ]),
      );
      expect(await Effect.runPromise(repository.all)).toHaveLength(4);
    });

    it("counts two records made at once as two", async () => {
      const repository = await make();
      await Effect.runPromise(
        Effect.all(
          Array.from({ length: 10 }, () =>
            repository.record({ pairId: "p1", userId: ana, name: "NoteSent", at: day1 }),
          ),
          { concurrency: "unbounded" },
        ),
      );
      const [row] = await Effect.runPromise(repository.all);
      expect(row?.count).toBe(10);
    });
    it("counts a detail by name and day, apart from the person, and sums its value", async () => {
      const repository = await make();
      await Effect.runPromise(
        Effect.all([
          repository.record({
            pairId: "p1",
            userId: ana,
            name: "ShopItemBought",
            at: day1,
            detail: "lamp",
            value: 30,
          }),
          repository.record({
            pairId: "p2",
            userId: ben,
            name: "ShopItemBought",
            at: day1Later,
            detail: "lamp",
            value: 30,
          }),
          repository.record({
            pairId: "p1",
            userId: ana,
            name: "ShopItemBought",
            at: day2,
            detail: "lamp",
            value: 30,
          }),
          repository.record({
            pairId: "p1",
            userId: ana,
            name: "CatChosen",
            at: day1,
            detail: "tabby",
          }),
          repository.record({ pairId: "p1", userId: ana, name: "CatPetted", at: day1 }),
        ]),
      );
      const details = await Effect.runPromise(repository.details);
      expect(details).toHaveLength(3);
      expect(details).toEqual(
        expect.arrayContaining([
          { name: "ShopItemBought", detail: "lamp", day: "2026-11-02", count: 2, total: 60 },
          { name: "ShopItemBought", detail: "lamp", day: "2026-11-03", count: 1, total: 30 },
          { name: "CatChosen", detail: "tabby", day: "2026-11-02", count: 1, total: 0 },
        ]),
      );
      // The person's count is kept by name, as for any event.
      expect(await Effect.runPromise(repository.all)).toHaveLength(5);
    });
  });
