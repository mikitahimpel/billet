import { Effect, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import type { OnboardingAnswer } from "@billet/contracts-domain/onboarding";
import { StoredOnboardingAnswer, type OnboardingRepository } from "../src/onboarding-repository.ts";

type AnswerJson = typeof OnboardingAnswer.Encoded;

const user = Schema.decodeSync(UserId);
const stored = Schema.decodeSync(StoredOnboardingAnswer);

const row = (
  userId: string,
  stepId: string,
  answer: AnswerJson,
  answeredAt = 1_000,
): StoredOnboardingAnswer => stored({ userId, stepId, version: "2026-11-04", answer, answeredAt });

const sorted = (rows: ReadonlyArray<StoredOnboardingAnswer>) =>
  rows.toSorted((a, b) => a.stepId.localeCompare(b.stepId));

/** Runs against every implementation. `make` returns an empty one in which `u1` and `u2` exist. */
export const describeOnboardingRepositoryContract = (
  name: string,
  make: () => Promise<OnboardingRepository["Service"]>,
) =>
  describe(`${name} (OnboardingRepository contract)`, () => {
    const run = <A, E>(effect: Effect.Effect<A, E>) => Effect.runPromise(effect);

    it("has nothing for an account that answered nothing", async () => {
      const repository = await make();
      expect(await run(repository.answersOf(user("u1")))).toEqual([]);
    });

    it("keeps one answer per account and step, each answer as given", async () => {
      const repository = await make();
      const answers = [
        row("u1", "age", { _tag: "Single", option: "age-25-34" }),
        row("u1", "goals", { _tag: "Multi", options: ["widgets", "raise-pet"] }),
        row("u1", "name", { _tag: "Text", text: "Лев 💛" }),
        row("u1", "pronouns", { _tag: "Skipped" }),
        row("u1", "steps", { _tag: "Range", value: 7 }),
        row("u2", "age", { _tag: "Skipped" }),
      ];
      for (const answer of answers) await run(repository.save(answer));
      expect(sorted(await run(repository.answersOf(user("u1"))))).toEqual(
        sorted(answers.slice(0, 5)),
      );
      expect(await run(repository.answersOf(user("u2")))).toEqual([answers[5]]);
    });

    it("replaces an answer with a later one, a skip with an answer and back", async () => {
      const repository = await make();
      await run(repository.save(row("u1", "age", { _tag: "Skipped" }, 1_000)));
      await run(repository.save(row("u1", "age", { _tag: "Single", option: "age-18-24" }, 2_000)));
      expect(await run(repository.answersOf(user("u1")))).toEqual([
        row("u1", "age", { _tag: "Single", option: "age-18-24" }, 2_000),
      ]);
      await run(repository.save(row("u1", "age", { _tag: "Skipped" }, 3_000)));
      expect(await run(repository.answersOf(user("u1")))).toEqual([
        row("u1", "age", { _tag: "Skipped" }, 3_000),
      ]);
    });

    it("keeps the newer answer when an older one arrives late, and takes a tie", async () => {
      const repository = await make();
      const newer = row("u1", "goals", { _tag: "Multi", options: ["widgets"] }, 5_000);
      await run(repository.save(newer));
      await run(repository.save(row("u1", "goals", { _tag: "Skipped" }, 4_000)));
      expect(await run(repository.answersOf(user("u1")))).toEqual([newer]);
      const tie = row("u1", "goals", { _tag: "Multi", options: ["draw-together"] }, 5_000);
      await run(repository.save(tie));
      expect(await run(repository.answersOf(user("u1")))).toEqual([tie]);
    });

    it("stores one row for the same answer sent twice at once", async () => {
      const repository = await make();
      const answer = row("u1", "name", { _tag: "Text", text: "Lev" });
      await run(Effect.all([repository.save(answer), repository.save(answer)], { concurrency: 2 }));
      expect(await run(repository.answersOf(user("u1")))).toEqual([answer]);
    });
  });
