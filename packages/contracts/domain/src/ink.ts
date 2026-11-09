import { Schema } from "effect";

/** `#RRGGBB`. */
export const Color = Schema.String.check(Schema.isPattern(/^#[0-9A-Fa-f]{6}$/));
export type Color = typeof Color.Type;

export const Point = Schema.Struct({ x: Schema.Finite, y: Schema.Finite });
export type Point = typeof Point.Type;

/** Full precision, used while drawing live. */
export const Stroke = Schema.Struct({
  color: Color,
  width: Schema.Finite,
  points: Schema.Array(Point),
});
export type Stroke = typeof Stroke.Type;

const CompactStroke = Schema.Struct({
  color: Color,
  width: Schema.Int,
  /** Flat quantised coordinates `[x0, y0, x1, y1, ...]`. */
  points: Schema.Array(Schema.Int).check(
    Schema.makeFilter((points) => points.length % 2 === 0 || "expected an even number of values"),
  ),
});

/** Travels inside a push, so it stays under about 3 KB. */
export const CompactStrokes = Schema.Struct({
  version: Schema.Literal(1),
  strokes: Schema.Array(CompactStroke),
});
export type CompactStrokes = typeof CompactStrokes.Type;
