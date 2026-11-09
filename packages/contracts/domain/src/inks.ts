import { Effect, Schema } from "effect";
import { Color } from "./ink.ts";

/** Never reused. */
export const InkId = Schema.String.check(
  Schema.isPattern(/^ink-[a-z0-9]+(-[a-z0-9]+)*$/),
  Schema.isMaxLength(40),
).pipe(Schema.brand("InkId"));
export type InkId = typeof InkId.Type;

/** `light` is drawn on light paper, `dark` on dark paper. */
export const Ink = Schema.Struct({
  id: InkId,
  /** English; the app shows its own name for the id. */
  name: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(40)),
  light: Color,
  dark: Color,
  /** In coins. */
  price: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
});
export type Ink = typeof Ink.Type;

const decodeInkId = Schema.decodeSync(InkId);

/** Owned from the start; a text note without an ink is written in it. */
export const freeInk: InkId = decodeInkId("ink-graphite");

const ink = (id: string, name: string, light: string, dark: string, price: number): Ink => ({
  id: decodeInkId(id),
  name,
  light,
  dark,
  price,
});

/** Canonical: an id stays once sold. One partner's purchase is both partners'. Prices and
 * colours are placeholders until the owner sets them. */
export const inks: ReadonlyArray<Ink> = [
  ink("ink-graphite", "Graphite", "#2B2B2E", "#ECEAE4", 0),
  ink("ink-rose", "Rose", "#D2456B", "#FF8FAB", 60),
  ink("ink-sea", "Sea", "#1F6FB2", "#7CC4FF", 60),
  ink("ink-moss", "Moss", "#3E7D3A", "#9BD88F", 60),
  ink("ink-ember", "Ember", "#D9622B", "#FFA36E", 60),
  ink("ink-plum", "Plum", "#6B3FA0", "#C3A2F0", 90),
  ink("ink-gold", "Gold", "#B08A1E", "#F2CF5B", 120),
];

export const inkOf = (id: string): Ink | undefined => inks.find((entry) => entry.id === id);

export const KnownInkId = InkId.check(
  Schema.makeFilter((id) => inkOf(id) !== undefined || `expected an ink the catalog sells`),
);

/** A note from before inks has none and decodes as `freeInk`; it is always encoded. */
export const NoteInk = KnownInkId.pipe(Schema.withDecodingDefaultKey(Effect.succeed(freeInk)));
