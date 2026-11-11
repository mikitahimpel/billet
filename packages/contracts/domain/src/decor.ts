import { Schema } from "effect";
import { IdempotencyKey } from "./ids.ts";
import { footprints } from "./decor-catalog.ts";
import { Placement, RoomItemId } from "./shop.ts";

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

const step = 0.05;
const reach = 0.49;
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
 * what stands on it share their floor. */
export const placementProblem = (
  placement: Placement,
  others: ReadonlyArray<Placement>,
): "unknown-piece" | "wrong-surface" | "outside-room" | "occupied" | undefined => {
  const size = footprints[placement.item];
  const span = spanOf(placement);
  if (size === undefined || span === undefined) return "unknown-piece";
  if ((size.mount === "wall") !== (placement.surface !== "floor")) return "wrong-surface";
  const outside =
    Math.abs(span.x) + span.halfX > reach + slack ||
    (placement.surface === "floor" && Math.abs(span.z) + span.halfZ > reach + slack);
  if (outside) return "outside-room";
  for (const other of others) {
    if (other.item === placement.item || other.surface !== placement.surface) continue;
    const otherSpan = spanOf(other);
    if (otherSpan === undefined) continue;
    if (placement.surface === "floor" && (size.flat || footprints[other.item]?.flat === true))
      continue;
    if (overlaps(span, otherSpan)) return "occupied";
  }
  return undefined;
};
