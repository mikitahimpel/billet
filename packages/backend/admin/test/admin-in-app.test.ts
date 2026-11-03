import { describe, expect, it } from "vitest";
import { ClientEventName } from "@billet/contracts-domain/metrics";
import type { EventRow } from "@billet/backend-metrics/funnel";
import { buildInApp, type DetailRow, topNames } from "../src/admin-in-app.ts";

const today = "2026-11-03";

const row = (
  name: EventRow["name"],
  day: string,
  pairId: string,
  userId: string,
  count = 1,
): EventRow => ({ name, day, pairId, userId, count, firstAt: 0 });

const detail = (name: string, value: string, day: string, count = 1, total = 0): DetailRow => ({
  name,
  detail: value,
  day,
  count,
  total,
});

describe("the Overview's In the app block", () => {
  it("lists every client event with a count per day, oldest first", () => {
    const inApp = buildInApp(
      [
        row("CatPetted", today, "p1", "u1", 3),
        row("CatPetted", today, "p1", "u2", 2),
        row("CatPetted", "2026-11-01", "p2", "u3"),
        row("NoteSent", today, "p1", "u1"),
      ],
      [],
      today,
      3,
    );
    expect(inApp.days).toEqual(["2026-11-01", "2026-11-02", "2026-11-03"]);
    expect(inApp.events.map(({ name }) => name)).toEqual(ClientEventName.literals);
    expect(inApp.events.find(({ name }) => name === "CatPetted")?.daily).toEqual([1, 0, 5]);
    expect(inApp.events.some(({ name }) => (name as string) === "NoteSent")).toBe(false);
  });

  it("counts the pairs that did each at least once in the last 7 days, never the unpaired", () => {
    const inApp = buildInApp(
      [
        row("ShopOpened", today, "p1", "u1"),
        row("ShopOpened", today, "p1", "u2"),
        row("ShopOpened", "2026-10-28", "p2", "u3"),
        row("ShopOpened", "2026-10-27", "p3", "u4"),
        row("ShopOpened", today, "", "u5"),
      ],
      [],
      today,
    );
    expect(inApp.events.find(({ name }) => name === "ShopOpened")?.pairs7d).toBe(2);
  });

  it("ranks the most chosen things over 30 days, with the stamps spent on bought ones", () => {
    const inApp = buildInApp(
      [],
      [
        detail("CatChosen", "tabby", today, 2),
        detail("CatChosen", "idolIlya", today, 5),
        detail("CatChosen", "tabby", "2026-10-20", 4),
        detail("CatChosen", "hero", "2026-10-01", 50),
        detail("ShopItemBought", "lamp", today, 2, 60),
      ],
      today,
    );
    expect(inApp.top.map(({ name }) => name)).toEqual(topNames);
    expect(inApp.top.find(({ name }) => name === "CatChosen")?.items).toEqual([
      { detail: "tabby", count: 6 },
      { detail: "idolIlya", count: 5 },
    ]);
    expect(inApp.top.find(({ name }) => name === "ShopItemBought")?.items).toEqual([
      { detail: "lamp", count: 2, total: 60 },
    ]);
  });

  it("keeps at most five per name", () => {
    const many = Array.from({ length: 8 }, (_, index) =>
      detail("RoomItemPlaced", `item-${index}`, today, index + 1),
    );
    const items = buildInApp([], many, today).top.find(
      ({ name }) => name === "RoomItemPlaced",
    )?.items;
    expect(items?.map(({ detail: id }) => id)).toEqual([
      "item-7",
      "item-6",
      "item-5",
      "item-4",
      "item-3",
    ]);
  });
});
