import { Clock, Context, Effect, Layer, Option, Schema, Semaphore } from "effect";
import { type EarnEvent, LocalDay, localDayOf } from "@billet/contracts-domain/coins";
import {
  GuessOption,
  GuessQuestionId,
  type GuessReveal,
  type GuessScore,
  type GuessTally,
} from "@billet/contracts-domain/guess";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { type GuessAnswerRequest, GuessResponse } from "@billet/contracts-http-api/guess";
import type { RoomDecision } from "./room-decision.ts";
import { RoomService } from "./room-service.ts";
import type { ActiveRoom } from "./room-state.ts";
import { RoomStore } from "./room-store.ts";
import { hash, shuffled } from "./seeded.ts";

/** Questions in a round, while the deck has that many. */
export const roundLength = 5;

const dayMillis = 86_400_000;
const decodeDay = Schema.decodeSync(LocalDay);

/** Days since 1970-01-01 of a calendar day. */
const dayNumber = (day: LocalDay): number => Date.parse(`${day}T00:00:00Z`) / dayMillis;

const dayAt = (number: number): LocalDay =>
  decodeDay(new Date(number * dayMillis).toISOString().slice(0, 10));

/** The Monday of the week `day` is in. 1970-01-01 was a Thursday, three days after a Monday. */
export const weekOf = (day: LocalDay): LocalDay => {
  const number = dayNumber(day);
  return dayAt(number - ((number + 3) % 7));
};

/** The offset the room counts its days in: the cat's, as for coins, else UTC. */
export const roomOffsetOf = (room: ActiveRoom): number => room.cat?.profile.utcOffsetSeconds ?? 0;

/** When the room day `day` ends, `utcOffsetSeconds` from UTC. */
export const closesAtOf = (day: LocalDay, utcOffsetSeconds: number): EpochMillis =>
  (dayNumber(day) + 1) * dayMillis - utcOffsetSeconds * 1000;

/**
 * Whom the round of `day` is about. It alternates by calendar day, so a missed day still hands the
 * next one to the other member; the pair id picks who starts.
 */
export const subjectOf = (room: ActiveRoom, day: LocalDay): UserId => {
  const [first, second] = room.members;
  return (dayNumber(day) + (hash(room.pairId) & 1)) % 2 === 0 ? first.user : second.user;
};

/**
 * The questions of the pair's next round. Each cycle walks its own seeded order of `deck`, and a
 * cycle ends once every question of the deck was asked in it, so none comes back before then.
 * `history` is the questions of every earlier round, oldest first; ids no longer in the deck count
 * for nothing. A round can finish one cycle and start the next.
 */
export const questionsFor = (
  deck: ReadonlyArray<GuessQuestionId>,
  history: ReadonlyArray<ReadonlyArray<GuessQuestionId>>,
  seed: string,
  count = roundLength,
): ReadonlyArray<GuessQuestionId> => {
  const ids = [...new Set(deck)].toSorted((a, b) => a - b);
  const inDeck = new Set(ids);
  let cycle = 0;
  let seen = new Set<GuessQuestionId>();
  const see = (id: GuessQuestionId) => {
    seen.add(id);
    if (seen.size === ids.length) {
      cycle += 1;
      seen = new Set();
    }
  };
  for (const id of history.flat()) if (inDeck.has(id)) see(id);
  const picked: Array<GuessQuestionId> = [];
  while (picked.length < Math.min(count, ids.length)) {
    const next = shuffled(ids, hash(`${seed}:${cycle}`)).find(
      (id) => !seen.has(id) && !picked.includes(id),
    );
    if (next === undefined) break;
    picked.push(next);
    see(next);
  }
  return picked;
};

/** The round of one room day, as the room stores it. */
export const GuessRoundRow = Schema.Struct({
  day: LocalDay,
  subject: UserId,
  questions: Schema.Array(GuessQuestionId),
});
export type GuessRoundRow = typeof GuessRoundRow.Type;

/** One member's locked answer to one question of a round. */
export const GuessAnswerRow = Schema.Struct({
  day: LocalDay,
  member: UserId,
  question: GuessQuestionId,
  option: GuessOption,
  at: EpochMillis,
});
export type GuessAnswerRow = typeof GuessAnswerRow.Type;

/** A member's points in the week that started on the Monday `week`. */
export const GuessWeekRow = Schema.Struct({
  week: LocalDay,
  member: UserId,
  points: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
});
export type GuessWeekRow = typeof GuessWeekRow.Type;

export const GuessRefusal = Schema.Literals(["NotOpen", "RoundClosed", "NotInRound", "Answered"]);
export type GuessRefusal = typeof GuessRefusal.Type;

/** What an answer does: refused, nothing (the same option again), or one row and maybe a score. */
export type GuessDecision =
  | { readonly _tag: "Refused"; readonly reason: GuessRefusal }
  | { readonly _tag: "Repeated" }
  | { readonly _tag: "Stored"; readonly write: GuessAnswerRow; readonly score?: GuessWeekRow };

const guesserOf = (members: readonly [UserId, UserId], round: GuessRoundRow): UserId =>
  members[0] === round.subject ? members[1] : members[0];

const optionOf = (answers: ReadonlyArray<GuessAnswerRow>, member: UserId, question: number) =>
  answers.find((answer) => answer.member === member && answer.question === question)?.option;

/** Each question opened, in round order, once both members answered all of them. */
export const revealOf = (
  members: readonly [UserId, UserId],
  round: GuessRoundRow,
  answers: ReadonlyArray<GuessAnswerRow>,
): ReadonlyArray<GuessReveal> | undefined => {
  const guesser = guesserOf(members, round);
  const reveal: Array<GuessReveal> = [];
  for (const question of round.questions) {
    const truth = optionOf(answers, round.subject, question);
    const guess = optionOf(answers, guesser, question);
    if (truth === undefined || guess === undefined) return undefined;
    reveal.push({ question, truth, guess, hit: truth === guess });
  }
  return reveal;
};

/**
 * What `by` answering `request` at `at` does, on the room day `today`. Pure. Only today's round
 * takes answers, so a round left half done closes, unscored, when its day ends. The answer that
 * completes the round scores it: a point to the guesser for each hit, in the round's week.
 */
export const decideAnswer = (
  members: readonly [UserId, UserId],
  round: GuessRoundRow,
  answers: ReadonlyArray<GuessAnswerRow>,
  by: UserId,
  request: GuessAnswerRequest,
  today: LocalDay,
  at: EpochMillis,
): GuessDecision => {
  if (request.round !== today || round.day !== today) {
    return { _tag: "Refused", reason: "RoundClosed" };
  }
  if (!round.questions.includes(request.question)) {
    return { _tag: "Refused", reason: "NotInRound" };
  }
  const mine = optionOf(answers, by, request.question);
  if (mine !== undefined) {
    return mine === request.option ? { _tag: "Repeated" } : { _tag: "Refused", reason: "Answered" };
  }
  const write: GuessAnswerRow = {
    day: round.day,
    member: by,
    question: request.question,
    option: request.option,
    at,
  };
  const reveal = revealOf(members, round, [...answers, write]);
  if (reveal === undefined) return { _tag: "Stored", write };
  const points = reveal.filter((question) => question.hit).length;
  const score = { week: weekOf(round.day), member: guesserOf(members, round), points };
  return { _tag: "Stored", write, score };
};

/** `weeks` after `score` was added to them. */
export const withScore = (
  weeks: ReadonlyArray<GuessWeekRow>,
  score: GuessWeekRow,
): ReadonlyArray<GuessWeekRow> => {
  const same = (row: GuessWeekRow) => row.week === score.week && row.member === score.member;
  const points = (weeks.find(same)?.points ?? 0) + score.points;
  return [...weeks.filter((row) => !same(row)), { ...score, points }];
};

/** The pair's score as `caller` sees it, in the week of `today`. */
export const scoreOf = (
  weeks: ReadonlyArray<GuessWeekRow>,
  caller: UserId,
  today: LocalDay,
): GuessScore => {
  const weekOfToday = weekOf(today);
  const tally = (rows: ReadonlyArray<GuessWeekRow>, of: (points: Array<number>) => number) => {
    const points = (mine: boolean) =>
      of(rows.filter((row) => (row.member === caller) === mine).map((row) => row.points));
    return { mine: points(true), partner: points(false) } satisfies GuessTally;
  };
  const sum = (points: Array<number>) => points.reduce((total, point) => total + point, 0);
  const best = (points: Array<number>) => Math.max(0, ...points);
  return {
    weekOf: weekOfToday,
    week: tally(
      weeks.filter((row) => row.week === weekOfToday),
      sum,
    ),
    allTime: tally(weeks, sum),
    bestWeek: tally(weeks, best),
  };
};

/**
 * The round as `caller` sees it. The partner's options never leave the room before the reveal:
 * only how many questions they answered.
 */
export const guessView = (
  members: readonly [UserId, UserId],
  round: GuessRoundRow,
  answers: ReadonlyArray<GuessAnswerRow>,
  weeks: ReadonlyArray<GuessWeekRow>,
  caller: UserId,
  today: LocalDay,
  utcOffsetSeconds: number,
): GuessResponse => {
  const reveal = revealOf(members, round, answers);
  return {
    round: {
      id: round.day,
      subject: round.subject,
      questions: round.questions,
      closesAt: closesAtOf(round.day, utcOffsetSeconds),
    },
    answers: answers
      .filter((answer) => answer.member === caller)
      .toSorted((a, b) => a.at - b.at)
      .map(({ question, option }) => ({ question, option })),
    partnerAnswered: answers.filter((answer) => answer.member !== caller).length,
    ...(reveal === undefined ? {} : { reveal }),
    score: scoreOf(weeks, caller, today),
  };
};

/** The question ids of the catalog the room picks rounds from. */
export class GuessDeck extends Context.Service<
  GuessDeck,
  { readonly questions: ReadonlyArray<GuessQuestionId> }
>()("@billet/backend-pair-room/GuessDeck") {}

/** The rounds, answers and weekly points of one room. Failures are defects, as for `RoomStore`. */
export class GuessStore extends Context.Service<
  GuessStore,
  {
    readonly round: (day: LocalDay) => Effect.Effect<Option.Option<GuessRoundRow>>;
    /** Every round, oldest first. */
    readonly rounds: Effect.Effect<ReadonlyArray<GuessRoundRow>>;
    /** Stores a new round; a round already stored for its day is kept. */
    readonly startRound: (round: GuessRoundRow) => Effect.Effect<void>;
    readonly answers: (day: LocalDay) => Effect.Effect<ReadonlyArray<GuessAnswerRow>>;
    readonly weeks: Effect.Effect<ReadonlyArray<GuessWeekRow>>;
    /** Stores `row` and, when given, adds `score.points` to that member's week, atomically. */
    readonly answer: (row: GuessAnswerRow, score?: GuessWeekRow) => Effect.Effect<void>;
    /** Deletes every round, answer and point: the pair is ending. */
    readonly forget: Effect.Effect<void>;
  }
>()("@billet/backend-pair-room/GuessStore") {}

export const GuessCommand = Schema.TaggedUnion({
  View: {},
  Answer: { round: LocalDay, question: GuessQuestionId, option: GuessOption },
});
export type GuessCommand = typeof GuessCommand.Type;

/** What a Who knows who command answers: the caller's round after it, or why it was refused. */
export const GuessResult = Schema.TaggedUnion({
  Done: { view: GuessResponse },
  Refused: { reason: GuessRefusal },
});
export type GuessResult = typeof GuessResult.Type;

/** What a command did, for the room to tell the sockets, the push lanes and the shop. */
export interface GuessOutcome {
  readonly result: GuessResult;
  /**
   * After an answer stored or repeated: how many questions of the round `member` has answered, of
   * how many, and whether this call stored one.
   */
  readonly progress?: {
    readonly round: LocalDay;
    readonly member: UserId;
    readonly answered: number;
    readonly of: number;
    readonly stored: boolean;
  };
  /** Whether the round is revealed after this answer. */
  readonly revealed: boolean;
  /** The coins the reveal paid. A repeated answer pays what a failed first try left unpaid. */
  readonly coins: ReadonlyArray<RoomDecision>;
}

/** A finished part to tell the partner about, while the round still waits for them. */
export interface GuessNotice {
  readonly recipient: UserId;
  /** What the member who finished did: answered about themselves, or guessed. */
  readonly role: "subject" | "guesser";
  readonly count: number;
}

const membersOf = (room: ActiveRoom): readonly [UserId, UserId] => [
  room.members[0].user,
  room.members[1].user,
];

/** Runs Who knows who commands against one room: load, start the day's round, decide, store. */
export class GuessRoom extends Context.Service<GuessRoom>()("@billet/backend-pair-room/GuessRoom", {
  make: Effect.gen(function* () {
    const store = yield* GuessStore;
    const room = yield* RoomStore;
    const coins = yield* RoomService;
    const deck = yield* GuessDeck;
    // Two answers at once each decide from the one before, so the round reveals and scores once.
    const lock = yield* Semaphore.make(1);

    const roundOf = (state: ActiveRoom, day: LocalDay) =>
      Effect.gen(function* () {
        const stored = yield* store.round(day);
        if (Option.isSome(stored)) return stored.value;
        const history = (yield* store.rounds).map((round) => round.questions);
        const round: GuessRoundRow = {
          day,
          subject: subjectOf(state, day),
          questions: questionsFor(deck.questions, history, state.pairId),
        };
        yield* store.startRound(round);
        return round;
      });

    const pay = (members: readonly [UserId, UserId], round: GuessRoundRow, by: UserId) =>
      Effect.gen(function* () {
        const reveal = revealOf(members, round, yield* store.answers(round.day)) ?? [];
        const guesser = guesserOf(members, round);
        const events: Array<readonly [UserId, EarnEvent]> = [
          ...reveal
            .filter((question) => question.hit)
            .map(
              (question) =>
                [
                  guesser,
                  { _tag: "GuessHit", round: round.day, question: question.question },
                ] as const,
            ),
          [by, { _tag: "RoundPlayed", round: round.day }],
        ];
        return yield* Effect.forEach(events, ([member, event]) =>
          coins.earn(member, event, undefined),
        );
      });

    const run = (by: UserId, command: GuessCommand): Effect.Effect<GuessOutcome> =>
      Effect.gen(function* () {
        const state = yield* room.load;
        if (state._tag !== "Active" || !state.members.some((member) => member.user === by)) {
          const result = GuessResult.cases.Refused.make({ reason: "NotOpen" });
          return { result, revealed: false, coins: [] };
        }
        const members = membersOf(state);
        const offset = roomOffsetOf(state);
        const now = yield* Clock.currentTimeMillis;
        const today = localDayOf(now, offset);
        const round = yield* roundOf(state, today);
        const answers = yield* store.answers(today);
        const weeks = yield* store.weeks;
        const view = (after: ReadonlyArray<GuessAnswerRow>, scored: ReadonlyArray<GuessWeekRow>) =>
          GuessResult.cases.Done.make({
            view: guessView(members, round, after, scored, by, today, offset),
          });
        if (command._tag === "View") {
          return { result: view(answers, weeks), revealed: false, coins: [] };
        }
        const { _tag, ...request } = command;
        const decision = decideAnswer(members, round, answers, by, request, today, now);
        if (decision._tag === "Refused") {
          const result = GuessResult.cases.Refused.make({ reason: decision.reason });
          return { result, revealed: false, coins: [] };
        }
        const stored = decision._tag === "Stored";
        if (stored) yield* store.answer(decision.write, decision.score);
        const after = stored ? [...answers, decision.write] : answers;
        const scored =
          stored && decision.score !== undefined ? withScore(weeks, decision.score) : weeks;
        const revealed = revealOf(members, round, after) !== undefined;
        return {
          result: view(after, scored),
          progress: {
            round: today,
            member: by,
            answered: after.filter((answer) => answer.member === by).length,
            of: round.questions.length,
            stored,
          },
          revealed,
          coins: revealed ? yield* pay(members, round, by) : [],
        };
      }).pipe(lock.withPermits(1));

    /**
     * Whom to tell that `member` finished their part of the round of `day`, while that round is
     * still today's and the partner has not finished theirs. A reveal is not pushed.
     */
    const notice = (day: LocalDay, member: UserId): Effect.Effect<GuessNotice | undefined> =>
      Effect.gen(function* () {
        const state = yield* room.load;
        if (state._tag !== "Active") return undefined;
        const members = membersOf(state);
        const recipient = members.find((user) => user !== member);
        const round = Option.getOrUndefined(yield* store.round(day));
        const now = yield* Clock.currentTimeMillis;
        if (recipient === undefined || round === undefined) return undefined;
        if (localDayOf(now, roomOffsetOf(state)) !== day) return undefined;
        const answers = yield* store.answers(day);
        const mine = answers.filter((answer) => answer.member === member).length;
        if (mine < round.questions.length || revealOf(members, round, answers) !== undefined) {
          return undefined;
        }
        const role = member === round.subject ? "subject" : "guesser";
        return { recipient, role, count: round.questions.length };
      });

    return { run, notice, forget: store.forget.pipe(lock.withPermits(1)) };
  }),
}) {
  static readonly layer = Layer.effect(GuessRoom, GuessRoom.make);
}
