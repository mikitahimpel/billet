import { Schema } from "effect";
import { Color, Point, Stroke } from "@billet/contracts-domain/ink";

export const PresenceState = Schema.Literals(["idle", "drawing"]);
export type PresenceState = typeof PresenceState.Type;

/** Picked by the sender; unique only among that sender's open strokes. */
export const LiveStrokeId = Schema.Int.check(
  Schema.isBetween({ minimum: 0, maximum: 2_147_483_647 }),
);
export type LiveStrokeId = typeof LiveStrokeId.Type;

/** Per `StrokePoints` frame; a sender batches every 30 to 50 ms. */
export const maxLivePoints = 64;

export const LivePoints = Schema.Array(Point).check(
  Schema.isNonEmpty(),
  Schema.isMaxLength(maxLivePoints),
);

export const ClientMessage = Schema.TaggedUnion({
  /** A socket that leaves `lastCatSeq` out is sent no cat frames. Each flag below subscribes to
   * its server message. */
  Resume: {
    lastSeq: Schema.Int,
    lastCatSeq: Schema.optionalKey(Schema.Int),
    activity: Schema.optionalKey(Schema.Boolean),
    /** Asks for every reaction change after this `rev`. Left out, none. */
    lastReactionRev: Schema.optionalKey(Schema.Int),
    shop: Schema.optionalKey(Schema.Boolean),
    lists: Schema.optionalKey(Schema.Boolean),
    moods: Schema.optionalKey(Schema.Boolean),
    guess: Schema.optionalKey(Schema.Boolean),
    riddle: Schema.optionalKey(Schema.Boolean),
  },
  /** From a client that does not stream. */
  Stroke: { stroke: Stroke },
  Presence: { state: PresenceState },
  /** Its points follow in `StrokePoints`. */
  StrokeBegin: { id: LiveStrokeId, color: Color, width: Schema.Finite },
  /** Canvas coordinates. */
  StrokePoints: { id: LiveStrokeId, points: LivePoints },
  StrokeEnd: { id: LiveStrokeId },
  /** For both partners. */
  Clear: {},
});
export type ClientMessage = typeof ClientMessage.Type;
