import { Schema } from "effect";
import { IdempotencyKey } from "./ids.ts";
import { baseHomes, footprints } from "./decor-catalog.ts";
import { DecorRoom, Placement, RoomItemId } from "./shop.ts";

/** `Place` stands a piece in the room or moves it; `Unplace` takes it back to the closet. */
export const LayoutChange = Schema.TaggedUnion({
  Place: { placement: Placement },
  Unplace: { item: RoomItemId },
});
export type LayoutChange = typeof LayoutChange.Type;

/** The caller's `id` is applied once: a repeat answers `duplicate`. */
export const LayoutRequest = Schema.Struct({ id: IdempotencyKey, change: LayoutChange });
export type LayoutRequest = typeof LayoutRequest.Type;

export const LayoutResult = Schema.Literals(["applied", "duplicate"]);
export type LayoutResult = typeof LayoutResult.Type;

const decodeItem = Schema.decodeSync(RoomItemId);

/** A piece of the room's own furniture: every pair has it and none is sold. */
export const isBasePiece = (item: string): boolean => item in baseHomes;

const bedroomPrefix = "base-bedroom-";

/** The room a piece of the room's own furniture belongs to; undefined for a bought piece, which stands
 * in either room. */
export const homeRoomOf = (item: string): DecorRoom | undefined =>
  item.startsWith(bedroomPrefix) ? "bedroom" : isBasePiece(item) ? "living" : undefined;

/** The room a placement stands in: the living room when it names none. */
export const roomOf = (placement: Placement): DecorRoom => placement.room ?? "living";

/** A placement as the room keeps it: the living room is never named, so a layout in it reads as before. */
export const normalizedPlacement = (placement: Placement): Placement => {
  const { room, ...rest } = placement;
  return room === undefined || room === "living" ? rest : placement;
};

/** The room as the pair arranged it: what they placed or moved, and the room's own furniture that was
 * neither moved nor put away, each at home. A room that never arranged anything is the default room. */
export const effectiveLayout = (
  layout: ReadonlyArray<Placement>,
  stowed: ReadonlyArray<string>,
): ReadonlyArray<Placement> => [
  ...Object.entries(baseHomes)
    .filter(([item]) => !stowed.includes(item) && !layout.some((placed) => placed.item === item))
    .map(([item, home]): Placement => {
      const placement: Placement = {
        item: decodeItem(item),
        surface: "floor",
        u: home.u,
        v: home.v,
        quarterTurns: 0,
      };
      return homeRoomOf(item) === "bedroom" ? { ...placement, room: "bedroom" } : placement;
    }),
  ...layout,
];

/** Whether `item` can be put away: each room keeps a bed or a sofa for the cat. */
export const canPutAway = (layout: ReadonlyArray<Placement>, item: string): boolean => {
  if (footprints[item]?.rest !== true) return true;
  const room = roomOfItem(layout, item);
  return layout.some(
    (placed) =>
      placed.item !== item && footprints[placed.item]?.rest === true && roomOf(placed) === room,
  );
};

/** Where `item` stands now: its placement's room, else its home room, else the living room. */
const roomOfItem = (layout: ReadonlyArray<Placement>, item: string): DecorRoom => {
  const placed = layout.find((placement) => placement.item === item);
  return placed === undefined ? (homeRoomOf(item) ?? "living") : roomOf(placed);
};

const step = 0.05;
/** How far a piece's edge may reach from the room's middle, per room. */
const reaches: Readonly<Record<DecorRoom, number>> = { living: 0.49, bedroom: 0.49 };
const slack = 0.001;

interface Span {
  readonly x: number;
  readonly z: number;
  readonly halfX: number;
  readonly halfZ: number;
}

const spanOf = (placement: Placement): Span | undefined => {
  const size = footprints[placement.item];
  if (size === undefined) return undefined;
  if (placement.surface !== "floor") {
    return { x: placement.u * step, z: 0, halfX: size.width / 2, halfZ: 0.01 };
  }
  if (placement.quarterTurns >= 4) {
    // At 45 degrees the box round the turned footprint, so a fit is never overstated.
    const half = ((size.width + size.depth) / 2) * Math.SQRT1_2;
    return { x: placement.u * step, z: placement.v * step, halfX: half, halfZ: half };
  }
  const turned = placement.quarterTurns % 2 === 1;
  return {
    x: placement.u * step,
    z: placement.v * step,
    halfX: (turned ? size.depth : size.width) / 2,
    halfZ: (turned ? size.width : size.depth) / 2,
  };
};

const overlaps = (a: Span, b: Span): boolean =>
  Math.abs(a.x - b.x) < a.halfX + b.halfX - slack &&
  Math.abs(a.z - b.z) < a.halfZ + b.halfZ - slack;

/** Why a placement is refused, or undefined when it fits among `others`. A flat piece (the rug) and
 * what stands on it share their floor; only pieces of the same room count as neighbours. */
export const placementProblem = (
  placement: Placement,
  others: ReadonlyArray<Placement>,
): "unknown-piece" | "wrong-surface" | "wrong-room" | "outside-room" | "occupied" | undefined => {
  const size = footprints[placement.item];
  const span = spanOf(placement);
  if (size === undefined || span === undefined) return "unknown-piece";
  if ((size.mount === "wall") !== (placement.surface !== "floor")) return "wrong-surface";
  const room = roomOf(placement);
  const home = homeRoomOf(placement.item);
  if (home !== undefined && home !== room) return "wrong-room";
  const reach = reaches[room];
  const outside =
    Math.abs(span.x) + span.halfX > reach + slack ||
    (placement.surface === "floor" && Math.abs(span.z) + span.halfZ > reach + slack);
  if (outside) return "outside-room";
  for (const other of others) {
    if (roomOf(other) !== room) continue;
    if (other.item === placement.item || other.surface !== placement.surface) continue;
    const otherSpan = spanOf(other);
    if (otherSpan === undefined) continue;
    if (placement.surface === "floor" && (size.flat || footprints[other.item]?.flat === true))
      continue;
    if (overlaps(span, otherSpan)) return "occupied";
  }
  return undefined;
};
