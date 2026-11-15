import { Schema } from "effect";
import { type CatEvent, drawGuessGame } from "./cat.ts";
import { EpochMillis } from "./ids.ts";

/**
 * Where an entry's coins came from or went, whatever its id looks like (the id prefix is only a
 * uniqueness scheme: a `refund:` id is an Apple refund, not the shop's Undo). `earn` is play, paid
 * by the server; `purchase` is a coin pack; `refund` takes a pack back and is the only kind that
 * can drive the balance below 0; `gift`, `bonus` and `admin` are coins given (the daily gift and
 * welcome coins, a finished collection, support); `spend` is a shop purchase. `buy` is what
 * `purchase` was called before; it stays so entries stored with it still decode, and is never
 * written.
 */
export const CoinEntryKind = Schema.Literals([
  "earn",
  "purchase",
  "spend",
  "refund",
  "gift",
  "bonus",
  "admin",
  "buy",
]);
export type CoinEntryKind = typeof CoinEntryKind.Type;

/** `<kind>:<what it came from>`, such as `earn:<cat entry id>` or `spend:<buy id>`. One per id. */
export const CoinEntryId = Schema.String.check(
  Schema.isPattern(/^[a-z]+:[A-Za-z0-9:._-]{1,100}$/),
).pipe(Schema.brand("CoinEntryId"));
export type CoinEntryId = typeof CoinEntryId.Type;

/** `amount` is signed: a spend is negative. `ref`: the cat entry, item, transaction or day. */
export const CoinEntry = Schema.Struct({
  id: CoinEntryId,
  kind: CoinEntryKind,
  amount: Schema.Int,
  ref: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(100)),
  at: EpochMillis,
});
export type CoinEntry = typeof CoinEntry.Type;

export type EarnSource = "care" | "notes" | "games" | "lists";

/** Per local day, 10 coins from play and about 13 for a fully active day with the gift and the streak. Rewards are small against the shop's
 * prices on purpose: the cheapest piece takes days and the top ones weeks (docs/economy.md).
 * `coin-pacing.test.ts` fails if an edit makes earning faster than that. */
export const dailyEarnCaps: Readonly<Record<EarnSource, number>> = {
  care: 2,
  notes: 3,
  games: 4,
  lists: 1,
};

/** Before the daily cap. */
export const rewardFor = (event: CatEvent): { source: EarnSource; coins: number } | undefined => {
  switch (event._tag) {
    case "Fed":
    case "Petted":
    case "Played":
    case "Watered":
      return { source: "care", coins: 1 };
    case "NoteShared":
      return { source: "notes", coins: event.kind === "Photo" ? 2 : 1 };
    case "GamePlayed":
      // Draw-guess carries its round's coins, which hints lower.
      return {
        source: "games",
        coins: event.game === drawGuessGame ? event.score : event.won ? 3 : 1,
      };
    case "Slept":
    case "Shooed":
      return undefined;
  }
};

/** On the pair's local calendar, the day the caps reset on. */
export const LocalDay = Schema.String.check(Schema.isPattern(/^\d{4}-\d{2}-\d{2}$/)).pipe(
  Schema.brand("LocalDay"),
);
export type LocalDay = typeof LocalDay.Type;

const decodeDay = Schema.decodeSync(LocalDay);

export const localDayOf = (at: EpochMillis, utcOffsetSeconds: number): LocalDay =>
  decodeDay(new Date(at + utcOffsetSeconds * 1000).toISOString().slice(0, 10));

const decodeEntryId = Schema.decodeSync(CoinEntryId);

export const EarnRef = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9._-]{1,80}$/)).pipe(
  Schema.brand("EarnRef"),
);
export type EarnRef = typeof EarnRef.Type;

const decodeEarnRef = Schema.decodeSync(EarnRef);

/** The server pays once per `ref`: the same wish, idea, item or note again earns nothing. */
export const EarnEvent = Schema.TaggedUnion({
  WishReceived: { wish: EarnRef },
  DateMatched: { idea: EarnRef },
  /** `question` is a `GuessQuestionId`. The room pays it at the reveal, never the app. */
  GuessHit: { round: LocalDay, question: Schema.Int.check(Schema.isGreaterThanOrEqualTo(1)) },
  /** Paid by the room, like a hit. */
  RoundPlayed: { round: LocalDay },
  /** Rating a planned date marks it done. */
  DateRated: { plan: EarnRef },
  /** Groceries earn nothing, so the app never sends those. */
  ListTicked: { item: EarnRef },
  MomentAdded: { moment: EarnRef },
  NoteAdded: { note: EarnRef },
});
export type EarnEvent = typeof EarnEvent.Type;

/** No `source`: once per ref is the only limit. The room's stored-note entries fill the `notes`
 * cap too, so a shared note can't earn past it. */
export const rewardForEarn = (
  event: EarnEvent,
): {
  readonly coins: number;
  readonly source?: EarnSource;
  readonly id: CoinEntryId;
  readonly ref: EarnRef;
} => {
  const of = (kind: string, ref: EarnRef, coins: number, source?: EarnSource) => ({
    coins,
    ref,
    id: decodeEntryId(`earn:${kind}:${ref}`),
    ...(source === undefined ? {} : { source }),
  });
  switch (event._tag) {
    case "WishReceived":
      return of("wish", event.wish, 5);
    case "DateMatched":
      return of("date", event.idea, 2);
    case "GuessHit":
      return of("guess", decodeEarnRef(`${event.round}.${event.question}`), 1);
    case "RoundPlayed":
      return of("round", decodeEarnRef(event.round), 2);
    case "DateRated":
      return of("plan", event.plan, 6);
    case "ListTicked":
      return of("list", event.item, 1, "lists");
    case "MomentAdded":
      return of("moment", event.moment, 2, "notes");
    case "NoteAdded":
      return of("note", event.note, 1, "notes");
  }
};
