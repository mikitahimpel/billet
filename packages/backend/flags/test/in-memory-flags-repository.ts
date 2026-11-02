import { Effect } from "effect";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { FlagsRepository, StoredAssignment } from "../src/flags-repository.ts";

/** The test double for `FlagsRepository`. Single-threaded, so each method is trivially atomic. */
export const makeInMemoryFlagsRepository = () => {
  const rows = new Map<string, StoredAssignment>();
  const keyOf = (pairId: PairId, experimentKey: string) => `${pairId}/${experimentKey}`;
  const of = (pairId: PairId) => [...rows.values()].filter((row) => row.pairId === pairId);

  const repository: FlagsRepository["Service"] = {
    find: (pairId) => Effect.sync(() => of(pairId)),
    saveMissing: (pairId, assignments) =>
      Effect.sync(() => {
        for (const row of assignments) {
          const key = keyOf(pairId, row.experimentKey);
          if (!rows.has(key)) rows.set(key, row);
        }
        return of(pairId);
      }),
  };
  return { repository, rows };
};
