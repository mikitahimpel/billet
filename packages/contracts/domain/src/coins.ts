import { Schema } from "effect";
import type { CatEvent } from "./cat.ts";
import { EpochMillis } from "./ids.ts";

/**
 * Where a coin entry came from. `earn` is care for the cat, paid by the server from the journal;
 * `spend` is a purchase in the shop. The others arrive with the shop and with coin packs.
 */
export const CoinEntryKind = Schema.Literals(["earn", "buy", "spend", "refund", "gift", "bonus"]);
export type CoinEntryKind = typeof CoinEntryKind.Type;

/** `<kind>:<what it came from>`, such as `earn:<cat entry id>` or `spend:<buy id>`. One per id. */
export const CoinEntryId = Schema.String.check(
  Schema.isPattern(/^[a-z]+:[A-Za-z0-9:._-]{1,100}$/),
).pipe(Schema.brand("CoinEntryId"));
export type CoinEntryId = typeof CoinEntryId.Type;

/**
 * One line of the pair's wallet. `amount` is signed: a spend is negative. `ref` names what it came
 * from: the cat entry, the item bought, the transaction or the day.
 */
export const CoinEntry = Schema.Struct({
  id: CoinEntryId,
  kind: CoinEntryKind,
  amount: Schema.Int,
  ref: Schema.String.check(Schema.isNonEmpty(), Schema.isMaxLength(100)),
  at: EpochMillis,
});
export type CoinEntry = typeof CoinEntry.Type;

/** The kinds of care that earn coins, each with its own daily cap. */
export type EarnSource = "care" | "notes" | "games" | "lists";

/**
 * The most coins each kind of care earns the pair in one local day. Placeholders until the owner
 * sets them: a caring day earns about 80 coins, so a 60-coin ink is a day's care.
 */
export const dailyEarnCaps: Readonly<Record<EarnSource, number>> = {
  care: 10,
  notes: 30,
  games: 40,
  lists: 15,
};

/**
 * What one journal entry earns before the daily cap, and the cap it counts against. Placeholders
 * like the caps. Sleep and shooing earn nothing.
 */
export const rewardFor = (event: CatEvent): { source: EarnSource; coins: number } | undefined => {
  switch (event._tag) {
    case "Fed":
    case "Petted":
    case "Played":
    case "Watered":
      return { source: "care", coins: 1 };
    case "NoteShared":
      return { source: "notes", coins: event.kind === "Photo" ? 10 : 5 };
    case "GamePlayed":
      return { source: "games", coins: event.won ? 10 : 3 };
    case "Slept":
    case "Shooed":
      return undefined;
  }
};

/** `YYYY-MM-DD` on the pair's local calendar, the day the caps reset on. */
export const LocalDay = Schema.String.check(Schema.isPattern(/^\d{4}-\d{2}-\d{2}$/)).pipe(
  Schema.brand("LocalDay"),
);
export type LocalDay = typeof LocalDay.Type;

const decodeDay = Schema.decodeSync(LocalDay);

/** The local day `at` falls on, `utcOffsetSeconds` from UTC. */
export const localDayOf = (at: EpochMillis, utcOffsetSeconds: number): LocalDay =>
  decodeDay(new Date(at + utcOffsetSeconds * 1000).toISOString().slice(0, 10));

const decodeEntryId = Schema.decodeSync(CoinEntryId);

/** What an earn in the app names: a wish, a date idea, a list item, a moment or a note. */
export const EarnRef = Schema.String.check(Schema.isPattern(/^[A-Za-z0-9._-]{1,80}$/)).pipe(
  Schema.brand("EarnRef"),
);
export type EarnRef = typeof EarnRef.Type;

/**
 * Something the couple did in the app that earns coins. The server pays it once per `ref`: the same
 * wish, idea, plan, item, moment or note again earns nothing more.
 */
export const EarnEvent = Schema.TaggedUnion({
  /** The partner confirmed a wished-for gift arrived. */
  WishReceived: { wish: EarnRef },
  /** Both partners said yes to the same date idea. */
  DateMatched: { idea: EarnRef },
  /** A planned date was rated, which marks it done. */
  DateRated: { plan: EarnRef },
  /** A "we want to" item was ticked. Groceries earn nothing, so the app never sends those. */
  ListTicked: { item: EarnRef },
  MomentAdded: { moment: EarnRef },
  NoteAdded: { note: EarnRef },
});
export type EarnEvent = typeof EarnEvent.Type;

/**
 * What an app earn pays before the daily cap, the cap it counts against (none: once per ref is the
 * only limit), and the entry id that makes it once. Moments and notes count against the `notes`
 * cap, which the room's own entries for stored notes fill too, so a shared note can't earn past
 * it. Placeholders mirroring the app's local amounts.
 */
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
      return of("wish", event.wish, 20);
    case "DateMatched":
      return of("date", event.idea, 10);
    case "DateRated":
      return of("plan", event.plan, 30);
    case "ListTicked":
      return of("list", event.item, 5, "lists");
    case "MomentAdded":
      return of("moment", event.moment, 10, "notes");
    case "NoteAdded":
      return of("note", event.note, 5, "notes");
  }
};
