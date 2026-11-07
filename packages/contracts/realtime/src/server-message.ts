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
import { LivePoints, LiveStrokeId, PresenceState } from "./client-message.ts";

/**
 * What the room sends a device. `seq` supports reconnect. The live stroke frames are the
 * partner's, relayed as they arrive and never stored or replayed.
 */
export const ServerMessage = Schema.TaggedUnion({
  Stroke: { seq: Schema.Int, stroke: Stroke },
  Presence: { state: PresenceState },
  NoteReceived: { seq: Schema.Int, note: Note },
  StrokeBegin: { id: LiveStrokeId, color: Color, width: Schema.Finite },
  /**
   * `relayedAt`: the room's clock (ms since 1970) when the frame reached it. Gaps between
   * frames' `relayedAt` are how the sender's frames arrived at the room. A receiver compares
   * them with its own arrival gaps to tell a delay on the way in from one on the way out, and
   * can replay a clump at the pace the room saw (#326). Older rooms leave it out.
   */
  StrokePoints: {
    id: LiveStrokeId,
    points: LivePoints,
    relayedAt: Schema.optionalKey(Schema.Int.check(Schema.isGreaterThanOrEqualTo(0))),
  },
  StrokeEnd: { id: LiveStrokeId },
  /** The partner's device left with this stroke still open: discard it, it will not end. */
  StrokeDropped: { id: LiveStrokeId },
  Clear: {},
  /** One cat journal entry, either partner's, sent once to each socket that resumed the journal. */
  CatEntryAdded: { entry: CatEntry },
  /** The cat was adopted, renamed or given a new look. */
  CatSaved: { cat: CatProfile },
  /** The user's Inbox count changed, sent to sockets that resumed with `activity: true`. */
  ActivityUnread: { unread: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)) },
  /** A reaction was set or taken back, sent to sockets that resumed with `lastReactionRev`. */
  ReactionChanged: { reaction: NoteReaction },
  /**
   * The pair's coins, inks, room pieces or wishlist changed, sent to sockets that resumed with
   * `shop: true`, and once on that resume.
   */
  ShopChanged: { shop: PairShop },
  /**
   * The pair's lists, every one of them, sent to sockets that resumed with `lists: true`: once on
   * that resume and after each change either partner makes.
   */
  ListsChanged: { lists: Schema.Array(SharedList) },
  /**
   * A member's latest check-in, sent to sockets that resumed with `moods: true`: each one the room
   * holds on the resume, then every new one.
   */
  MoodChanged: { checkIn: MoodCheckIn },
  /**
   * Both partners swiped ♥ on one Pick tonight card, sent to every socket that resumed with
   * `lists: true`, the swiper's own included.
   */
  MatchFound: { match: PickMatch },
  /**
   * The partner answered another question of the Who knows who round of `round`: `answered` is how
   * many they have now. Never which option. Sent to the other member's sockets that resumed with
   * `guess: true`.
   */
  GuessProgress: {
    round: LocalDay,
    answered: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
  },
  /**
   * Both members answered the whole round of `round`: every question opened, in round order, and
   * the score after it as the socket's own user sees it. Sent to every socket that resumed with
   * `guess: true`, the answerer's own included.
   */
  GuessRevealed: { round: LocalDay, reveal: Schema.Array(GuessReveal), score: GuessScore },
  /**
   * A draw-guess riddle was sent, tried, hinted or ended, as the socket's own user sees it: the
   * guesser gets no `word` while it is open. Sent to every socket that resumed with `riddle: true`.
   */
  RiddleChanged: { riddle: Riddle },
});
export type ServerMessage = typeof ServerMessage.Type;
