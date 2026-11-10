import { Schema } from "effect";
import { IdempotencyKey } from "./ids.ts";
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

/** The footprint, in metres across and into the room with no turn, of each piece the app places. A
 * wall piece has its width only. The app has the same table. */
const footprints: Readonly<
  Record<string, { width: number; depth: number; mount: "floor" | "wall" }>
> = {
  armchair: { width: 0.36, depth: 0.3, mount: "floor" },
  bookcase: { width: 0.3, depth: 0.12, mount: "floor" },
  donutbed: { width: 0.34, depth: 0.34, mount: "floor" },
  lamp: { width: 0.14, depth: 0.14, mount: "floor" },
  lantern: { width: 0.1, depth: 0.1, mount: "floor" },
  monstera: { width: 0.22, depth: 0.22, mount: "floor" },
  print: { width: 0.2, depth: 0, mount: "wall" },
  rug: { width: 0.6, depth: 0.6, mount: "floor" },
  teatable: { width: 0.26, depth: 0.26, mount: "floor" },
  tower: { width: 0.2, depth: 0.2, mount: "floor" },
  yarn: { width: 0.12, depth: 0.12, mount: "floor" },
  mouse: { width: 0.08, depth: 0.05, mount: "floor" },
};

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
    if (placement.surface === "floor" && (placement.item === "rug" || other.item === "rug"))
      continue;
    if (overlaps(span, otherSpan)) return "occupied";
  }
  return undefined;
};
