import { Schema } from "effect";
import { Color, Point, Stroke } from "@billet/contracts-domain/ink";

export const PresenceState = Schema.Literals(["idle", "drawing"]);
export type PresenceState = typeof PresenceState.Type;

/**
 * Names one stroke while it is being drawn. The sender picks it, and it only has to be unique
 * among that sender's open strokes.
 */
export const LiveStrokeId = Schema.Int.check(
  Schema.isBetween({ minimum: 0, maximum: 2_147_483_647 }),
);
export type LiveStrokeId = typeof LiveStrokeId.Type;

/** The most points one `StrokePoints` frame may carry; a sender batches every 30 to 50 ms. */
export const maxLivePoints = 64;

export const LivePoints = Schema.Array(Point).check(
  Schema.isNonEmpty(),
  Schema.isMaxLength(maxLivePoints),
);

export const ClientMessage = Schema.TaggedUnion({
  /**
   * Reconnect, asking for every note after `lastSeq`, and every cat journal entry after
   * `lastCatSeq`. A socket that leaves `lastCatSeq` out is sent no cat frames.
   */
  Resume: {
    lastSeq: Schema.Int,
    lastCatSeq: Schema.optionalKey(Schema.Int),
    /** Asks for `ActivityUnread` whenever the user's Inbox count changes. */
    activity: Schema.optionalKey(Schema.Boolean),
    /** Asks for every reaction change after this `rev`, and each one after. Left out, none. */
    lastReactionRev: Schema.optionalKey(Schema.Int),
    /** Asks for `ShopChanged` now and whenever the pair's shop changes. */
    shop: Schema.optionalKey(Schema.Boolean),
    /** Asks for `ListsChanged` now and whenever one of the pair's lists changes. */
    lists: Schema.optionalKey(Schema.Boolean),
    /** Asks for `MoodChanged` with each member's latest check-in now, and each new one. */
    moods: Schema.optionalKey(Schema.Boolean),
    /** Asks for `GuessProgress` and `GuessRevealed` as the pair plays Who knows who. */
    guess: Schema.optionalKey(Schema.Boolean),
    /** Asks for `RiddleChanged` each time a draw-guess riddle is sent, tried, hinted or ended. */
    riddle: Schema.optionalKey(Schema.Boolean),
  },
  /** A whole stroke at once, from a client that does not stream. */
  Stroke: { stroke: Stroke },
  Presence: { state: PresenceState },
  /** A stroke starts on the shared canvas; its points follow in `StrokePoints`. */
  StrokeBegin: { id: LiveStrokeId, color: Color, width: Schema.Finite },
  /** The next points of an open stroke, in canvas coordinates. */
  StrokePoints: { id: LiveStrokeId, points: LivePoints },
  StrokeEnd: { id: LiveStrokeId },
  /** Wipes the shared canvas for both partners. */
  Clear: {},
});
export type ClientMessage = typeof ClientMessage.Type;
