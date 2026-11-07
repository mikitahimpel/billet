import { Effect, Layer, Option, Schema } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vitest";
import { LocalDay } from "@billet/contracts-domain/coins";
import { GuessQuestionId } from "@billet/contracts-domain/guess";
import type { UserId } from "@billet/contracts-domain/ids";
import {
  decideAnswer,
  type GuessAnswerRow,
  GuessDeck,
  GuessRoom,
  type GuessRoundRow,
  GuessStore,
  type GuessWeekRow,
  guessView,
  questionsFor,
  scoreOf,
  subjectOf,
  weekOf,
  withScore,
} from "../src/guess.ts";
import { RoomService } from "../src/room-service.ts";
import type { ActiveRoom } from "../src/room-state.ts";
import { countingIds, memoryStore } from "./memory-store.ts";
import { active, alice, bob, mallory, vacant, withCat } from "./samples.ts";

const day = Schema.decodeSync(LocalDay);
const question = Schema.decodeSync(GuessQuestionId);
const ids = (...numbers: ReadonlyArray<number>) => numbers.map((n) => question(n));
const deck = ids(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12);
const members = [alice, bob] as const;

/** Noon UTC on Thursday 2026-11-05. */
const noon = Date.UTC(2026, 10, 5, 12);
const hour = 3_600_000;
const today = day("2026-11-05");

const round: GuessRoundRow = { day: today, subject: alice, questions: ids(1, 2, 3, 4, 5) };

/** `member` answers every question of `round` with `options`, in order, through the pure rules. */
const answerAll = (
  answers: ReadonlyArray<GuessAnswerRow>,
  member: UserId,
  options: ReadonlyArray<number>,
) => {
  let rows = answers;
  let score: GuessWeekRow | undefined;
  round.questions.forEach((id, index) => {
    const request = { round: today, question: id, option: options[index] ?? 0 };
    const decision = decideAnswer(members, round, rows, member, request, today, noon + index);
    if (decision._tag !== "Stored") throw new Error(decision._tag);
    rows = [...rows, decision.write];
    score = decision.score ?? score;
  });
  return { rows, score };
};

describe("the room day", () => {
  it("starts its week on Monday and ends it on Sunday", () => {
    expect(weekOf(day("2026-11-02"))).toBe("2026-11-02");
    expect(weekOf(day("2026-11-05"))).toBe("2026-11-02");
    expect(weekOf(day("2026-11-08"))).toBe("2026-11-02");
    expect(weekOf(day("2026-11-09"))).toBe("2026-11-09");
    expect(weekOf(day("2027-01-01"))).toBe("2026-12-28");
  });

  it("is about the other member each day, the same on every call", () => {
    const subjects = ["2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08"].map((d) =>
      subjectOf(active, day(d)),
    );
    expect(subjects[0]).not.toBe(subjects[1]);
    expect(subjects[0]).toBe(subjects[2]);
    expect(subjects[1]).toBe(subjects[3]);
    expect(new Set(subjects)).toEqual(new Set([alice, bob]));
    expect(subjectOf(active, today)).toBe(subjects[0]);
  });
});

describe("the questions of a round", () => {
  it("are five of the deck, the same for the same pair and history", () => {
    const first = questionsFor(deck, [], "pair-1");
    expect(first).toHaveLength(5);
    expect(new Set(first).size).toBe(5);
    expect(first.every((id) => deck.includes(id))).toBe(true);
    expect(questionsFor(deck, [], "pair-1")).toEqual(first);
    expect(questionsFor(deck.toReversed(), [], "pair-1")).toEqual(first);
  });

  it("do not come back until the pair has seen the whole deck", () => {
    const history: Array<ReadonlyArray<GuessQuestionId>> = [];
    for (let n = 0; n < 7; n += 1) history.push(questionsFor(deck, history, "pair-1"));
    const asked = history.flat();
    // 12 questions take two rounds and two of the third; the third's other three start cycle two.
    expect(new Set(asked.slice(0, 12)).size).toBe(12);
    expect(new Set(asked.slice(12, 24)).size).toBe(12);
    expect(new Set(asked.slice(24, 35)).size).toBe(11);
    expect(history.every((questions) => new Set(questions).size === questions.length)).toBe(true);
  });

  it("follow the deck as it grows, and ignore questions it dropped", () => {
    const first = questionsFor(ids(1, 2, 3, 4, 5, 6), [], "pair-1");
    const next = questionsFor(ids(1, 2, 3, 4, 5, 6, 7, 8), [first], "pair-1");
    expect(next.filter((id) => first.includes(id))).toHaveLength(2);
    expect(next).toEqual(expect.arrayContaining(ids(7, 8)));
    expect(questionsFor(ids(2, 3), [ids(1, 2, 9)], "pair-1")).toEqual(ids(3, 2));
  });

  it("take what a small deck has", () => {
    expect(questionsFor(ids(4, 9), [], "pair-1").toSorted()).toEqual(ids(4, 9));
    expect(questionsFor([], [], "pair-1")).toEqual([]);
  });
});

describe("an answer", () => {
  const request = (id: number, option: number) => ({
    round: today,
    question: question(id),
    option,
  });

  it("locks: the same option again changes nothing, another one is refused", () => {
    const first = decideAnswer(members, round, [], alice, request(1, 2), today, noon);
    if (first._tag !== "Stored") throw new Error(first._tag);
    const rows = [first.write];
    expect(decideAnswer(members, round, rows, alice, request(1, 2), today, noon)).toEqual({
      _tag: "Repeated",
    });
    expect(decideAnswer(members, round, rows, alice, request(1, 3), today, noon)).toEqual({
      _tag: "Refused",
      reason: "Answered",
    });
    expect(decideAnswer(members, round, rows, bob, request(1, 3), today, noon)._tag).toBe("Stored");
  });

  it("is only for a question of today's round", () => {
    expect(decideAnswer(members, round, [], alice, request(6, 0), today, noon)).toEqual({
      _tag: "Refused",
      reason: "NotInRound",
    });
    const yesterday = { ...request(1, 0), round: day("2026-11-04") };
    expect(decideAnswer(members, round, [], alice, yesterday, today, noon)).toEqual({
      _tag: "Refused",
      reason: "RoundClosed",
    });
    expect(
      decideAnswer(members, round, [], alice, request(1, 0), day("2026-11-06"), noon + 24 * hour),
    ).toEqual({ _tag: "Refused", reason: "RoundClosed" });
  });
});

describe("the round as each member sees it", () => {
  it("hides the partner's options until both answered everything, counting them only", () => {
    const { rows } = answerAll([], bob, [3, 3, 3, 3, 3]);
    const partial = guessView(members, round, rows, [], alice, today, 0);
    expect(partial.answers).toEqual([]);
    expect(partial.partnerAnswered).toBe(5);
    expect(partial.reveal).toBeUndefined();
    expect(JSON.stringify(partial)).not.toContain('"option"');

    const mine = guessView(members, round, rows, [], bob, today, 0);
    expect(mine.answers.map((answer) => answer.option)).toEqual([3, 3, 3, 3, 3]);
    expect(mine.partnerAnswered).toBe(0);
    expect(mine.round).toEqual({
      id: today,
      subject: alice,
      questions: round.questions,
      closesAt: Date.UTC(2026, 10, 6),
    });
  });

  it("reveals each question with the truth, the guess and a hit or miss, and scores the guesser", () => {
    const truths = answerAll([], alice, [0, 1, 2, 3, 0]);
    expect(truths.score).toBeUndefined();
    const { rows, score } = answerAll(truths.rows, bob, [0, 1, 0, 3, 1]);
    expect(score).toEqual({ week: day("2026-11-02"), member: bob, points: 3 });
    const view = guessView(members, round, rows, withScore([], score!), alice, today, 0);
    expect(view.reveal).toEqual([
      { question: 1, truth: 0, guess: 0, hit: true },
      { question: 2, truth: 1, guess: 1, hit: true },
      { question: 3, truth: 2, guess: 0, hit: false },
      { question: 4, truth: 3, guess: 3, hit: true },
      { question: 5, truth: 0, guess: 1, hit: false },
    ]);
    expect(view.score.week).toEqual({ mine: 0, partner: 3 });
  });
});

describe("the score", () => {
  const weeks: ReadonlyArray<GuessWeekRow> = [
    { week: day("2026-10-26"), member: alice, points: 9 },
    { week: day("2026-10-26"), member: bob, points: 4 },
    { week: day("2026-11-02"), member: alice, points: 2 },
    { week: day("2026-11-02"), member: bob, points: 6 },
  ];

  it("tallies the week from Monday, all time, and each member's best week", () => {
    expect(scoreOf(weeks, alice, day("2026-11-08"))).toEqual({
      weekOf: "2026-11-02",
      week: { mine: 2, partner: 6 },
      allTime: { mine: 11, partner: 10 },
      bestWeek: { mine: 9, partner: 6 },
    });
    expect(scoreOf(weeks, bob, day("2026-11-09"))).toEqual({
      weekOf: "2026-11-09",
      week: { mine: 0, partner: 0 },
      allTime: { mine: 10, partner: 11 },
      bestWeek: { mine: 6, partner: 9 },
    });
  });

  it("adds a round's points to the guesser's week", () => {
    const after = withScore(weeks, { week: day("2026-11-02"), member: bob, points: 3 });
    expect(scoreOf(after, bob, today).week).toEqual({ mine: 9, partner: 2 });
    expect(after).toHaveLength(4);
  });
});

/** A `GuessStore` in memory. */
const memoryGuessStore = () => {
  const memory = {
    rounds: [] as Array<GuessRoundRow>,
    answers: [] as Array<GuessAnswerRow>,
    weeks: [] as ReadonlyArray<GuessWeekRow>,
    started: 0,
  };
  const layer = Layer.succeed(GuessStore, {
    round: (d) => Effect.sync(() => Option.fromNullishOr(memory.rounds.find((r) => r.day === d))),
    rounds: Effect.sync(() => memory.rounds.toSorted((a, b) => (a.day < b.day ? -1 : 1))),
    startRound: (r) =>
      Effect.sync(() => {
        if (memory.rounds.some((old) => old.day === r.day)) return;
        memory.started += 1;
        memory.rounds.push(r);
      }),
    answers: (d) => Effect.sync(() => memory.answers.filter((answer) => answer.day === d)),
    weeks: Effect.sync(() => memory.weeks),
    answer: (row, score) =>
      Effect.sync(() => {
        memory.answers.push(row);
        if (score !== undefined) memory.weeks = withScore(memory.weeks, score);
      }),
    forget: Effect.sync(() => {
      memory.rounds = [];
      memory.answers = [];
      memory.weeks = [];
    }),
  });
  return { memory, layer };
};

describe("GuessRoom", () => {
  const roomWith = (state: ActiveRoom | typeof vacant) => {
    const rooms = memoryStore();
    rooms.memory.state = state;
    const guesses = memoryGuessStore();
    const coins = Effect.runSync(
      RoomService.make.pipe(Effect.provide(Layer.merge(rooms.layer, countingIds()))),
    );
    const guess = Effect.runSync(
      GuessRoom.make.pipe(
        Effect.provide(
          Layer.mergeAll(
            rooms.layer,
            guesses.layer,
            Layer.succeed(RoomService, coins),
            Layer.succeed(GuessDeck, { questions: deck }),
          ),
        ),
      ),
    );
    return { guess, rooms, guesses };
  };

  const at =
    (millis: number) =>
    <A>(effect: Effect.Effect<A>) =>
      Effect.runPromise(
        TestClock.setTime(millis).pipe(Effect.andThen(effect), Effect.provide(TestClock.layer())),
      );

  const viewOf = async (guess: ReturnType<typeof roomWith>["guess"], by: UserId, millis = noon) => {
    const { result } = await at(millis)(guess.run(by, { _tag: "View" }));
    if (result._tag !== "Done") throw new Error(result.reason);
    return result.view;
  };

  /** `by` answers every question of today's round with `option`. */
  const play = async (
    guess: ReturnType<typeof roomWith>["guess"],
    by: UserId,
    option: number,
    millis = noon,
  ) => {
    const view = await viewOf(guess, by, millis);
    const outcomes = [];
    for (const id of view.round.questions) {
      outcomes.push(
        await at(millis)(
          guess.run(by, { _tag: "Answer", round: view.round.id, question: id, option }),
        ),
      );
    }
    return outcomes;
  };

  it("keeps one round per room day, the same for both members", async () => {
    const { guess, guesses } = roomWith(active);
    const first = await viewOf(guess, alice);
    expect(await viewOf(guess, bob, noon + hour)).toMatchObject({ round: first.round });
    expect(guesses.memory.started).toBe(1);
    expect(first.round.id).toBe(today);
    expect(first.round.subject).toBe(subjectOf(active, today));
    expect(first.round.questions).toEqual(questionsFor(deck, [], active.pairId));
  });

  it("counts the day in the cat's time zone, as coins do", async () => {
    const { guess } = roomWith(withCat);
    // 23:30 UTC is already the next day an hour east of UTC.
    const late = await viewOf(guess, alice, Date.UTC(2026, 10, 5, 23, 30));
    expect(late.round.id).toBe("2026-11-06");
    expect(late.round.closesAt).toBe(Date.UTC(2026, 10, 6, 23));
  });

  it("reveals and scores once both finished, paying each hit and the round once", async () => {
    const { guess, rooms } = roomWith(active);
    const subject = subjectOf(active, today);
    const guesser = subject === alice ? bob : alice;
    const parts = await play(guess, subject, 1);
    expect(parts.at(-1)).toMatchObject({
      progress: { round: today, member: subject, answered: 5, of: 5, stored: true },
      revealed: false,
      coins: [],
    });
    const guesses = await play(guess, guesser, 1);
    const last = guesses.at(-1)!;
    expect(last.revealed).toBe(true);
    expect(last.result._tag === "Done" && last.result.view.reveal).toHaveLength(5);
    expect(rooms.memory.coins.map((entry) => [entry.id, entry.amount])).toEqual([
      ...(await viewOf(guess, alice)).round.questions.map((id) => [`earn:guess:${today}.${id}`, 2]),
      [`earn:round:${today}`, 10],
    ]);
    const view = await viewOf(guess, guesser);
    expect(view.score).toMatchObject({ week: { mine: 5, partner: 0 }, allTime: { mine: 5 } });

    // A retry of the last answer pays nothing more and scores nothing more.
    const [id] = view.round.questions;
    const again = await at(noon)(
      guess.run(guesser, { _tag: "Answer", round: today, question: id!, option: 1 }),
    );
    expect(again.progress?.stored).toBe(false);
    expect(
      again.coins.every((d) => d._tag === "Accepted" && d.outputs[0]?._tag === "CoinsRepeated"),
    ).toBe(true);
    expect(rooms.memory.coins).toHaveLength(6);
    expect((await viewOf(guess, guesser)).score.week.mine).toBe(5);
  });

  it("closes a half-finished round unscored when its day ends, and starts one about the other member", async () => {
    const { guess, rooms } = roomWith(active);
    const subject = subjectOf(active, today);
    await play(guess, subject, 0);
    const tomorrow = noon + 24 * hour;
    const late = await at(tomorrow)(
      guess.run(subject === alice ? bob : alice, {
        _tag: "Answer",
        round: today,
        question: (await viewOf(guess, alice)).round.questions[0]!,
        option: 0,
      }),
    );
    expect(late.result).toEqual({ _tag: "Refused", reason: "RoundClosed" });
    const next = await viewOf(guess, alice, tomorrow);
    expect(next.round.id).toBe("2026-11-06");
    expect(next.round.subject).not.toBe(subject);
    expect(next.answers).toEqual([]);
    expect(next.partnerAnswered).toBe(0);
    expect(next.score.allTime).toEqual({ mine: 0, partner: 0 });
    expect(rooms.memory.coins).toEqual([]);
  });

  it("tells the partner when a member finished their part, until the round reveals", async () => {
    const { guess } = roomWith(active);
    const subject = subjectOf(active, today);
    const guesser = subject === alice ? bob : alice;
    expect(await at(noon)(guess.notice(today, subject))).toBeUndefined();
    await play(guess, subject, 2);
    expect(await at(noon)(guess.notice(today, subject))).toEqual({
      recipient: guesser,
      role: "subject",
      count: 5,
    });
    expect(await at(noon + 24 * hour)(guess.notice(today, subject))).toBeUndefined();
    await play(guess, guesser, 2);
    expect(await at(noon)(guess.notice(today, guesser))).toBeUndefined();
  });

  it("refuses a caller who is not a member, and a room not open", async () => {
    expect((await at(noon)(roomWith(active).guess.run(mallory, { _tag: "View" }))).result).toEqual({
      _tag: "Refused",
      reason: "NotOpen",
    });
    expect((await at(noon)(roomWith(vacant).guess.run(alice, { _tag: "View" }))).result._tag).toBe(
      "Refused",
    );
  });

  it("forgets every round and point", async () => {
    const { guess, guesses } = roomWith(active);
    await play(guess, alice, 0);
    await at(noon)(guess.forget);
    expect(guesses.memory).toMatchObject({ rounds: [], answers: [], weeks: [] });
  });
});
