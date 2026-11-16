import { Effect, Option } from "effect";
import type { LocalDay } from "@billet/contracts-domain/coins";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { DisplayName } from "@billet/contracts-http-api/pair";
import type { PairProfileRepository } from "../src/pair-profile-repository.ts";

/** The test double for `PairProfileRepository`. A pair's day stays after the pair ends. */
export const makeInMemoryPairProfileRepository = (): PairProfileRepository["Service"] => {
  const names = new Map<UserId, DisplayName>();
  const days = new Map<PairId, LocalDay>();
  return {
    setName: (userId, name) =>
      Effect.sync(() => void (name === null ? names.delete(userId) : names.set(userId, name))),
    names: (users) =>
      Effect.sync(() =>
        users.flatMap((userId) => {
          const displayName = names.get(userId);
          return displayName === undefined ? [] : [{ userId, displayName }];
        }),
      ),
    setTogetherSince: (pairId, day, ifUnset) =>
      Effect.sync(() => {
        if (ifUnset && days.has(pairId)) return false;
        days.set(pairId, day);
        return true;
      }),
    togetherSince: (pairId) => Effect.sync(() => Option.fromNullishOr(days.get(pairId))),
  };
};
