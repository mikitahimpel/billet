import { Schema } from "effect";
import { describe, expect, it } from "vitest";
import type { LayoutChange } from "@billet/contracts-domain/decor";
import { type Placement, RoomItemId } from "@billet/contracts-domain/shop";
import { decide } from "../src/decide.ts";
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
  if (decision._tag !== "Accepted") throw new Error(`rejected: ${decision.rejection._tag}`);
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
    const moved = accepted(first, place(2, spot("armchair", 0, 6))).state;
    expect(moved.layout).toEqual([spot("armchair", 0, 6)]);
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
      room = accepted(room, place(n, spot("yarn", n % 2 === 0 ? -4 : -5, 6))).state;
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
    expect(accepted(first, place(3, spot("yarn", 5, -6))).state.layout).toHaveLength(2);
  });

  it("lets a piece stand on a rug", () => {
    const withRug: ActiveRoom = { ...owning, items: [...owning.items, piece("monstera")] };
    const first = accepted(withRug, place(1, spot("rug", 0, 0))).state;
    expect(accepted(first, place(2, spot("monstera", 0, 0))).state.layout).toHaveLength(2);
  });

  it("refuses a room not open", () => {
    expect(decide({ _tag: "Vacant" }, place(1, spot("armchair", 0, 0)))._tag).toBe("Rejected");
  });
});
