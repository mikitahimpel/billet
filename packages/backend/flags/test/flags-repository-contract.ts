import { Effect, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { FlagsRepository, StoredAssignment } from "../src/flags-repository.ts";

const pair = Schema.decodeSync(PairId);
const key = Schema.decodeSync(ExperimentKey);
const variant = Schema.decodeSync(VariantId);

const row = (
  pairId: string,
  experiment: string,
  chosen: string,
  assignedAt = 1_000,
): StoredAssignment => ({
  pairId: pair(pairId),
  experimentKey: key(experiment),
  variant: variant(chosen),
  assignedAt,
});

const sorted = (rows: ReadonlyArray<StoredAssignment>) =>
  rows.toSorted((a, b) => a.experimentKey.localeCompare(b.experimentKey));

/**
 * The behaviour every `FlagsRepository` must have. Run it against each implementation, so the
 * in-memory fake can't drift from the real one. `make` must return an empty repository.
 */
export const describeFlagsRepositoryContract = (
  name: string,
  make: () => Promise<FlagsRepository["Service"]>,
) =>
  describe(`${name} (FlagsRepository contract)`, () => {
    it("has nothing for a pair that never entered an experiment", async () => {
      const repository = await make();
      expect(await Effect.runPromise(repository.find(pair("p1")))).toEqual([]);
    });

    it("stores the assignments it is given and returns everything the pair has", async () => {
      const repository = await make();
      const saved = await Effect.runPromise(
        repository.saveMissing(pair("p1"), [row("p1", "a", "x"), row("p1", "b", "y")]),
      );
      expect(sorted(saved)).toEqual([row("p1", "a", "x"), row("p1", "b", "y")]);
      expect(sorted(await Effect.runPromise(repository.find(pair("p1"))))).toEqual(sorted(saved));
    });

    it("never changes an assignment the pair already has", async () => {
      const repository = await make();
      await Effect.runPromise(repository.saveMissing(pair("p1"), [row("p1", "a", "x")]));
      const again = await Effect.runPromise(
        repository.saveMissing(pair("p1"), [row("p1", "a", "other", 9_000), row("p1", "b", "y")]),
      );
      expect(sorted(again)).toEqual([row("p1", "a", "x"), row("p1", "b", "y")]);
    });

    it("keeps pairs apart", async () => {
      const repository = await make();
      await Effect.runPromise(repository.saveMissing(pair("p1"), [row("p1", "a", "x")]));
      await Effect.runPromise(repository.saveMissing(pair("p2"), [row("p2", "a", "y")]));
      expect(await Effect.runPromise(repository.find(pair("p1")))).toEqual([row("p1", "a", "x")]);
      expect(await Effect.runPromise(repository.find(pair("p2")))).toEqual([row("p2", "a", "y")]);
    });

    it("lets both partners store at once without conflict or a second row", async () => {
      const repository = await make();
      const results = await Effect.runPromise(
        Effect.all(
          [
            repository.saveMissing(pair("p1"), [row("p1", "a", "x")]),
            repository.saveMissing(pair("p1"), [row("p1", "a", "x")]),
          ],
          { concurrency: "unbounded" },
        ),
      );
      expect(results.map((rows) => rows.length)).toEqual([1, 1]);
      expect(await Effect.runPromise(repository.find(pair("p1")))).toHaveLength(1);
    });
  });
