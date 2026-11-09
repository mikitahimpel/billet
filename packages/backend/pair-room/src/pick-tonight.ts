import { Clock, Context, Effect, Layer, Schema, Semaphore } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { ListItemText, TmdbImagePath } from "@billet/contracts-domain/list";
import { PickChoice, type PickMatch, PickTitle } from "@billet/contracts-domain/pick-tonight";
import {
  type PickSwipeRequest,
  PickTonightResponse,
} from "@billet/contracts-http-api/pick-tonight";
import { RoomStore } from "./room-store.ts";

/** A Pick tonight session: two ♥ make a match only this close together, and older swipes lapse. */
export const pickSessionMillis = 24 * 60 * 60_000;

/** One member's swipe on one card, as the room stores it: their latest on that card. */
export const PickRow = Schema.Struct({
  member: UserId,
  title: PickTitle,
  choice: PickChoice,
  name: ListItemText,
  posterPath: Schema.optionalKey(TmdbImagePath),
  at: EpochMillis,
});
export type PickRow = typeof PickRow.Type;

/** The card a swipe is on, as one string: `item:<id>`, `movie:<tmdb>` or `tv:<tmdb>`. */
export const pickKeyOf = (title: PickTitle): string => {
  switch (title._tag) {
    case "Item":
      return `item:${title.item}`;
    case "Title":
      return `${title.kind}:${title.tmdb}`;
  }
};

const sameCard = (a: PickRow, b: PickRow) => pickKeyOf(a.title) === pickKeyOf(b.title);

const matchOf = (later: PickRow): PickMatch => ({
  title: later.title,
  name: later.name,
  ...(later.posterPath === undefined ? {} : { posterPath: later.posterPath }),
  at: later.at,
});

/** What a swipe does: the row to store, if anything changes, and the match it makes, if any. */
export interface PickDecision {
  readonly write?: PickRow;
  readonly match?: PickMatch;
}

/**
 * Pure. The same choice on a card again in the session changes nothing, so a retry never rematches.
 */
export const decidePick = (
  rows: ReadonlyArray<PickRow>,
  by: UserId,
  request: PickSwipeRequest,
  at: EpochMillis,
): PickDecision => {
  const write: PickRow = {
    member: by,
    title: request.title,
    choice: request.choice,
    name: request.name,
    ...(request.posterPath === undefined ? {} : { posterPath: request.posterPath }),
    at,
  };
  const inSession = (row: PickRow) => at - row.at < pickSessionMillis;
  const mine = rows.find((row) => row.member === by && sameCard(row, write) && inSession(row));
  if (mine?.choice === request.choice) return {};
  if (request.choice !== "want") return { write };
  const partner = rows.some(
    (row) => row.member !== by && sameCard(row, write) && row.choice === "want" && inSession(row),
  );
  return partner ? { write, match: matchOf(write) } : { write };
};

/** Each card both members swiped ♥ within one session of each other, newest first. */
export const pickMatches = (
  rows: ReadonlyArray<PickRow>,
  now: EpochMillis,
): ReadonlyArray<PickMatch> => {
  const live = rows.filter((row) => now - row.at < pickSessionMillis && row.choice === "want");
  const byCard = new Map<string, Array<PickRow>>();
  for (const row of live) {
    const key = pickKeyOf(row.title);
    byCard.set(key, [...(byCard.get(key) ?? []), row]);
  }
  return [...byCard.values()]
    .flatMap((wants) => {
      const members = new Set(wants.map((row) => row.member));
      if (members.size < 2) return [];
      const later = wants.toSorted((a, b) => b.at - a.at)[0];
      return later === undefined ? [] : [matchOf(later)];
    })
    .toSorted((a, b) => b.at - a.at);
};

/** The session ending at `now` as `caller` sees it. */
export const pickView = (
  rows: ReadonlyArray<PickRow>,
  caller: UserId,
  now: EpochMillis,
  match?: PickMatch,
): PickTonightResponse => {
  const live = rows.filter((row) => now - row.at < pickSessionMillis);
  return {
    swipes: live
      .filter((row) => row.member === caller)
      .map(({ title, choice, at }) => ({ title, choice, at })),
    partnerPicked: live.filter((row) => row.member !== caller).length,
    matches: pickMatches(live, now),
    ...(match === undefined ? {} : { match }),
  };
};

/** The swipes of one room. Failures are defects, as for `RoomStore`. */
export class PickTonightStore extends Context.Service<
  PickTonightStore,
  {
    readonly since: (since: EpochMillis) => Effect.Effect<ReadonlyArray<PickRow>>;
    /** Writes `row` over the member's swipe and prunes before `pruneBefore`, atomically. */
    readonly put: (row: PickRow, pruneBefore: EpochMillis) => Effect.Effect<void>;
    /** Deletes every swipe: the pair is ending. */
    readonly forget: Effect.Effect<void>;
  }
>()("@billet/backend-pair-room/PickTonightStore") {}

export const PickTonightCommand = Schema.TaggedUnion({
  View: {},
  Swipe: {
    title: PickTitle,
    choice: PickChoice,
    name: ListItemText,
    posterPath: Schema.optionalKey(TmdbImagePath),
  },
});
export type PickTonightCommand = typeof PickTonightCommand.Type;

/** What a Pick tonight command answers: the caller's session after it, or that the room is not open. */
export const PickTonightResult = Schema.TaggedUnion({
  Done: { view: PickTonightResponse },
  Refused: { reason: Schema.Literals(["NotOpen"]) },
});
export type PickTonightResult = typeof PickTonightResult.Type;

/** A match to tell the partner about: the member who did not make it, and the match. */
export interface MatchNotice {
  readonly recipient: UserId;
  readonly match: PickMatch;
}

/** Runs Pick tonight commands against one room: load, decide, store, view. */
export class PickTonightRoom extends Context.Service<PickTonightRoom>()(
  "@billet/backend-pair-room/PickTonightRoom",
  {
    make: Effect.gen(function* () {
      const store = yield* PickTonightStore;
      const room = yield* RoomStore;
      // Like the room's lock: two swipes at once each decide from the one before, so a card both
      // partners swipe ♥ at the same moment makes one match.
      const lock = yield* Semaphore.make(1);

      const run = (by: UserId, command: PickTonightCommand): Effect.Effect<PickTonightResult> =>
        Effect.gen(function* () {
          const state = yield* room.load;
          if (state._tag !== "Active" || !state.members.some((member) => member.user === by)) {
            return PickTonightResult.cases.Refused.make({ reason: "NotOpen" });
          }
          const now = yield* Clock.currentTimeMillis;
          const rows = yield* store.since(now - pickSessionMillis);
          if (command._tag === "View") {
            return PickTonightResult.cases.Done.make({ view: pickView(rows, by, now) });
          }
          const { _tag, ...request } = command;
          const { write, match } = decidePick(rows, by, request, now);
          if (write === undefined) {
            return PickTonightResult.cases.Done.make({ view: pickView(rows, by, now) });
          }
          yield* store.put(write, now - pickSessionMillis);
          const after = [
            ...rows.filter((row) => !(row.member === by && sameCard(row, write))),
            write,
          ];
          return PickTonightResult.cases.Done.make({ view: pickView(after, by, now, match) });
        }).pipe(lock.withPermits(1));

      /**
       * The match `key` made, while both still want the card, and whom to tell: the first swiper.
       */
      const notice = (key: string, at: EpochMillis): Effect.Effect<MatchNotice | undefined> =>
        Effect.gen(function* () {
          const rows = (yield* store.since(at - pickSessionMillis)).filter(
            (row) => pickKeyOf(row.title) === key && row.choice === "want",
          );
          const later = rows.find((row) => row.at === at);
          const earlier = rows.find((row) => later !== undefined && row.member !== later.member);
          return later === undefined || earlier === undefined
            ? undefined
            : { recipient: earlier.member, match: matchOf(later) };
        });

      return { run, notice, forget: store.forget.pipe(lock.withPermits(1)) };
    }),
  },
) {
  static readonly layer = Layer.effect(PickTonightRoom, PickTonightRoom.make);
}
