import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import {
  canPutAway,
  effectiveLayout,
  homeRoomOf,
  roomOf,
  type LayoutChange,
} from "@billet/contracts-domain/decor";
import { Placement, RoomItemId } from "@billet/contracts-domain/shop";
import { decide } from "../src/decide.ts";
import { shopOf } from "../src/shop-view.ts";
import { RoomCommand } from "../src/room-command.ts";
import type { RoomDecision } from "../src/room-decision.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { active, alice, mallory, uuid } from "./samples.ts";

const piece = Schema.decodeUnknownSync(RoomItemId);
const spot = (
  item: string,
  u: number,
  v = 0,
  surface: Placement["surface"] = "floor",
): Placement => ({
  item: piece(item),
  surface,
  u,
  v,
  quarterTurns: 0,
});

const owning: ActiveRoom = { ...active, items: [piece("armchair"), piece("yarn"), piece("print")] };

const change = (n: number, what: LayoutChange, by = alice) =>
  RoomCommand.cases.ChangeLayout.make({ by, id: uuid(n), change: what });
const place = (n: number, placement: Placement, by = alice) =>
  change(n, { _tag: "Place", placement }, by);

const accepted = (room: ActiveRoom, command: RoomCommand): RoomDecision & { _tag: "Accepted" } => {
  const decision = decide(room, command);
  if (decision._tag !== "Accepted")
    throw new Error(`rejected: ${JSON.stringify(decision.rejection)}`);
  return decision;
};

const reason = (room: ActiveRoom, command: RoomCommand) => {
  const decision = decide(room, command);
  return decision._tag === "Rejected" && decision.rejection._tag === "LayoutRefused"
    ? decision.rejection.reason
    : undefined;
};

describe("arranging the room", () => {
  it("stands an owned piece and tells the room the whole layout", () => {
    const decision = accepted(owning, place(1, spot("armchair", -2, 6)));
    expect(decision.state.layout).toEqual([spot("armchair", -2, 6)]);
    expect(decision.outputs).toEqual([
      { _tag: "LayoutChanged", layout: [spot("armchair", -2, 6)] },
    ]);
  });

  it("moves a piece by placing it again, and takes it back with Unplace", () => {
    const first = accepted(owning, place(1, spot("armchair", -2, 6))).state;
    const moved = accepted(first, place(2, spot("armchair", -1, 6))).state;
    expect(moved.layout).toEqual([spot("armchair", -1, 6)]);
    const gone = accepted(moved, change(3, { _tag: "Unplace", item: piece("armchair") })).state;
    expect(gone.layout).toEqual([]);
  });

  it("applies an id once and answers a repeat without changing anything", () => {
    const first = accepted(owning, place(1, spot("armchair", -2, 6))).state;
    const repeat = accepted(first, place(1, spot("armchair", 3, 6)));
    expect(repeat.state.layout).toEqual([spot("armchair", -2, 6)]);
    expect(repeat.outputs).toEqual([{ _tag: "LayoutRepeated" }]);
  });

  it("keeps the newest ids only", () => {
    let room = owning;
    for (let n = 1; n <= 70; n++) {
      room = accepted(room, place(n, spot("yarn", n % 2 === 0 ? -2 : -1, 5))).state;
    }
    expect(room.layoutLog).toHaveLength(64);
    expect(room.layoutLog.at(-1)).toBe(uuid(70));
  });

  it("refuses a piece the pair does not own, a stranger, and what does not fit", () => {
    expect(reason(owning, place(1, spot("tower", -2, 6)))).toBe("not-owned");
    expect(decide(owning, place(2, spot("armchair", -2, 6), mallory))._tag).toBe("Rejected");
    expect(reason(owning, place(3, spot("armchair", 9, 9)))).toBe("outside-room");
    expect(reason(owning, place(4, spot("armchair", 0, 0, "backWall")))).toBe("wrong-surface");
    expect(reason(owning, place(5, spot("print", 0, 0, "floor")))).toBe("wrong-surface");
  });

  it("refuses two pieces in one place, so two partners cannot overlap", () => {
    const first = accepted(owning, place(1, spot("armchair", -2, 6))).state;
    expect(reason(first, place(2, spot("yarn", -2, 6)))).toBe("occupied");
    expect(accepted(first, place(3, spot("yarn", 6, -3))).state.layout).toHaveLength(2);
  });

  it("measures a piece turned 45 degrees by the box round it, and keeps the 90 degree layouts valid", () => {
    const room: ActiveRoom = { ...owning, stowed: [piece("base-donutbed")] };
    const diagonal = (u: number) => ({ ...spot("armchair", u, 0), quarterTurns: 4 });
    expect(accepted(room, place(1, diagonal(5))).state.layout).toEqual([diagonal(5)]);
    expect(reason(room, place(2, diagonal(6)))).toBe("outside-room");
    expect(accepted(room, place(3, spot("armchair", 6, 0))).state.layout).toHaveLength(1);
    const first = accepted(room, place(4, diagonal(0))).state;
    expect(reason(first, place(5, spot("yarn", 4, 0)))).toBe("occupied");
    expect(() =>
      Schema.decodeUnknownSync(Placement)({ ...spot("armchair", 0, 0), quarterTurns: 8 }),
    ).toThrow();
    for (const turns of [0, 1, 2, 3, 5, 7]) {
      expect(
        Schema.decodeUnknownSync(Placement)({ ...spot("armchair", 0, 0), quarterTurns: turns })
          .quarterTurns,
      ).toBe(turns);
    }
  });

  it("lets a piece stand on a rug", () => {
    const withRug: ActiveRoom = { ...owning, items: [...owning.items, piece("monstera")] };
    const first = accepted(withRug, place(1, spot("rug", 0, 0))).state;
    expect(accepted(first, place(2, spot("monstera", 0, 5))).state.layout).toHaveLength(2);
  });

  it("knows the props of the catalog, a flat cushion is stood on, a wall clock hangs", () => {
    const props: ActiveRoom = {
      ...owning,
      items: [piece("windowseat"), piece("floorcushion-sage"), piece("books"), piece("clock")],
    };
    const first = accepted(props, place(1, spot("floorcushion-sage", 0, 5))).state;
    expect(accepted(first, place(2, spot("books", 0, 5))).state.layout).toHaveLength(2);
    expect(accepted(first, place(3, spot("clock", 4, 0, "backWall"))).state.layout).toHaveLength(2);
    expect(reason(props, place(4, spot("windowseat", 0, 0, "backWall")))).toBe("wrong-surface");
    expect(reason(props, place(5, spot("hammock", 0, 0)))).toBe("not-owned");
  });

  it("refuses a room not open", () => {
    expect(decide({ _tag: "Vacant" }, place(1, spot("armchair", 0, 0)))._tag).toBe("Rejected");
  });
});

describe("the room's own furniture", () => {
  it("stands where the room has it until the pair moves it, with no change stored", () => {
    expect(owning.layout).toEqual([]);
    expect(reason(owning, place(1, spot("armchair", 1, -1)))).toBe("occupied");
    expect(reason(owning, place(2, spot("armchair", -5, 0)))).toBe("occupied");
  });

  it("moves a piece of it like any other, and frees where it stood", () => {
    const moved = accepted(owning, place(1, spot("base-cattree", 7, 0))).state;
    expect(moved.layout).toEqual([spot("base-cattree", 7, 0)]);
    expect(reason(moved, place(2, spot("yarn", 7, 0)))).toBe("occupied");
    expect(reason(owning, place(3, spot("yarn", 7, -7)))).toBe("occupied");
    expect(accepted(moved, place(4, spot("yarn", 7, -7))).state.layout).toHaveLength(2);
    expect(reason(owning, place(5, spot("base-cattree", 1, -1)))).toBe("occupied");
  });

  it("owns it without buying: no sale, no ownership check", () => {
    expect(shopOf(owning)).toMatchObject({ layout: [], stowed: [] });
    expect(accepted(owning, place(1, spot("base-plant", -4, 4))).state.layout).toHaveLength(1);
    expect(reason(owning, place(2, spot("base-plant", 0, 0, "backWall")))).toBe("wrong-surface");
  });

  it("puts a piece away, remembers it, and stands it again on a place", () => {
    const away = accepted(owning, change(1, { _tag: "Unplace", item: piece("base-plant") })).state;
    expect(away.stowed).toEqual(["base-plant"]);
    expect(away.layout).toEqual([]);
    expect(shopOf(away)).toMatchObject({ layout: [], stowed: ["base-plant"] });
    expect(accepted(away, place(2, spot("yarn", -8, -8))).state.layout).toHaveLength(1);
    const back = accepted(away, place(3, spot("base-plant", 7, 3))).state;
    expect(back.stowed).toEqual([]);
    expect(back.layout).toContainEqual(spot("base-plant", 7, 3));
  });

  it("keeps a bed or a sofa for the cat: the last one cannot be put away", () => {
    const away = (n: number, item: string) => change(n, { _tag: "Unplace", item: piece(item) });
    expect(reason(owning, away(1, "base-donutbed"))).toBe("last-rest");
    const sofa = accepted(owning, place(2, spot("armchair", -2, 6))).state;
    const bedGone = accepted(sofa, away(3, "base-donutbed")).state;
    expect(bedGone.stowed).toEqual(["base-donutbed"]);
    expect(reason(bedGone, away(4, "armchair"))).toBe("last-rest");
    expect(accepted(bedGone, away(5, "base-plant")).state.stowed).toHaveLength(2);
  });
});

describe("arranging the bedroom", () => {
  const bedroom = (item: string, u: number, v = 0): Placement => ({
    ...spot(item, u, v),
    room: "bedroom",
  });
  const away = (n: number, item: string) => change(n, { _tag: "Unplace", item: piece(item) });

  it("keeps the two rooms apart: a spot taken in one is free in the other", () => {
    const one = accepted(owning, place(1, spot("armchair", -2, 6))).state;
    const both = accepted(one, place(2, bedroom("yarn", -5, 4))).state;
    expect(both.layout).toEqual([spot("armchair", -2, 6), bedroom("yarn", -5, 4)]);
    expect(reason(both, place(3, spot("yarn", -2, 6)))).toBe("occupied");
    expect(reason(both, place(4, spot("yarn", -4, -4)))).toBeUndefined();
    expect(reason(both, place(5, bedroom("armchair", -2, 6)))).toBe("occupied");
  });

  it("moves a piece from one room to the other by placing it again", () => {
    const one = accepted(owning, place(1, spot("yarn", -4, -4))).state;
    const moved = accepted(one, place(2, bedroom("yarn", -5, 5))).state;
    expect(moved.layout).toEqual([bedroom("yarn", -5, 5)]);
  });

  it("never names the living room, so a layout in it reads as before", () => {
    const named = { ...spot("armchair", -2, 6), room: "living" as const };
    expect(accepted(owning, place(1, named)).state.layout).toEqual([spot("armchair", -2, 6)]);
  });

  it("knows the room a piece belongs to and refuses an unknown room", () => {
    expect(() =>
      Schema.decodeUnknownSync(Placement)({ ...spot("armchair", 0, 0), room: "attic" }),
    ).toThrow();
    expect(homeRoomOf("base-bedroom-bed")).toBe("bedroom");
    expect(homeRoomOf("base-plant")).toBe("living");
    expect(homeRoomOf("armchair")).toBeUndefined();
    expect(roomOf(spot("armchair", 0, 0))).toBe("living");
    expect(roomOf(bedroom("armchair", 0, 0))).toBe("bedroom");
  });

  it("keeps a bed or sofa in each room", () => {
    const layout = [spot("armchair", -4, 0), bedroom("donutbed", 4, 0)];
    expect(canPutAway(layout, "donutbed")).toBe(false);
    expect(canPutAway([...layout, bedroom("armchair-round", 0, 5)], "donutbed")).toBe(true);
  });

  it("stands the bedroom's own furniture at home in the bedroom, not the living room", () => {
    const standing = effectiveLayout([], []);
    expect(standing.find((placed) => placed.item === "base-bedroom-bed")).toMatchObject({
      u: 1,
      v: -3,
      room: "bedroom",
    });
    expect(standing.find((placed) => placed.item === "base-plant")?.room).toBeUndefined();
    expect(standing.filter((placed) => roomOf(placed) === "bedroom")).toHaveLength(9);
  });

  it("moves the bed in the bedroom and refuses it in the living room", () => {
    const moved = accepted(owning, place(1, bedroom("base-bedroom-bed", 2, -3))).state;
    expect(moved.layout).toEqual([bedroom("base-bedroom-bed", 2, -3)]);
    expect(reason(owning, place(2, spot("base-bedroom-bed", 1, -3)))).toBe("wrong-room");
  });

  it("refuses a piece on the bed and keeps a bed in the bedroom", () => {
    expect(reason(owning, place(1, bedroom("base-bedroom-nightstand", 1, -3)))).toBe("occupied");
    const one = accepted(owning, away(1, "base-bedroom-catbed")).state;
    expect(reason(one, away(2, "base-bedroom-bed"))).toBe("last-rest");
    expect(reason(one, away(3, "base-donutbed"))).toBe("last-rest");
  });
});
