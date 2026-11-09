import { Schema } from "effect";
import { CatEntry, CatProfile } from "@billet/contracts-domain/cat";
import { Color, Stroke } from "@billet/contracts-domain/ink";
import { MoodCheckIn } from "@billet/contracts-domain/mood";
import { Note } from "@billet/contracts-domain/note";
import { NoteReaction } from "@billet/contracts-domain/reaction";
import { SharedList } from "@billet/contracts-domain/list";
import { PickMatch } from "@billet/contracts-domain/pick-tonight";
import { LocalDay } from "@billet/contracts-domain/coins";
import { GuessReveal, GuessScore } from "@billet/contracts-domain/guess";
import { Riddle } from "@billet/contracts-domain/riddle";
import { PairShop } from "@billet/contracts-domain/shop";
import { LivePoints, LiveStrokeId } from "./client-message.ts";

/**
 * The partner as the room sees them: `away` while they have no open socket, else what they last
 * said. A device never sends `away`; the room derives it.
 */
export const PartnerPresence = Schema.Literals(["idle", "drawing", "away"]);
export type PartnerPresence = typeof PartnerPresence.Type;

/** `seq` supports reconnect. Live stroke frames are relayed as they arrive, never stored or
 * replayed. */
export const ServerMessage = Schema.TaggedUnion({
  Stroke: { seq: Schema.Int, stroke: Stroke },
  /**
   * The partner's presence: sent on connect, when their first socket opens or their last one
   * closes, and when they start or stop drawing. Older rooms never send `away`.
   */
  Presence: { state: PartnerPresence },
  NoteReceived: { seq: Schema.Int, note: Note },
  StrokeBegin: { id: LiveStrokeId, color: Color, width: Schema.Finite },
  /** `relayedAt`: epoch ms when the frame reached the room, absent from older rooms. Lets a
   * receiver tell an inbound delay from an outbound one and replay a clump at the room's pace. */
  StrokePoints: {
    id: LiveStrokeId,
    points: LivePoints,
    relayedAt: Schema.optionalKey(Schema.Int.check(Schema.isGreaterThanOrEqualTo(0))),
  },
  StrokeEnd: { id: LiveStrokeId },
  /** The partner's device left with this stroke still open: discard it, it will not end. */
  StrokeDropped: { id: LiveStrokeId },
  Clear: {},
  /** Sent once to each socket that resumed the journal. */
  CatEntryAdded: { entry: CatEntry },
  CatSaved: { cat: CatProfile },
  /** Sent to sockets that resumed with `activity: true`. */
  ActivityUnread: { unread: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)) },
  /** Set or taken back. Sent to sockets that resumed with `lastReactionRev`. */
  ReactionChanged: { reaction: NoteReaction },
  /** Sent to sockets that resumed with `shop: true`, and once on that resume. */
  ShopChanged: { shop: PairShop },
  /** Every list, to sockets that resumed with `lists: true`: on that resume and each change. */
  ListsChanged: { lists: Schema.Array(SharedList) },
  /** To sockets that resumed with `moods: true`: each held check-in on resume, then each new. */
  MoodChanged: { checkIn: MoodCheckIn },
  /** Sent to every socket that resumed with `lists: true`, the swiper's own included. */
  MatchFound: { match: PickMatch },
  /** `answered`: how many the partner has answered, never which option. Sent to the other
   * member's sockets that resumed with `guess: true`. */
  GuessProgress: {
    round: LocalDay,
    answered: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
  },
  /** In round order, with the score as the socket's own user sees it. Sent to every socket that
   * resumed with `guess: true`, the answerer's own included. */
  GuessRevealed: { round: LocalDay, reveal: Schema.Array(GuessReveal), score: GuessScore },
  /** As the socket's user sees it: the guesser gets no `word` while it is open. Sent to every
   * socket that resumed with `riddle: true`. */
  RiddleChanged: { riddle: Riddle },
});
export type ServerMessage = typeof ServerMessage.Type;
