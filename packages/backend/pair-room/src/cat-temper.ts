import type { CatEvent, CatTemper } from "@billet/contracts-domain/cat";
import type { EpochMillis } from "@billet/contracts-domain/ids";

/** Where every trait starts, and the bounds that keep any of them from fixing what the cat does. */
export const temperStart = 0.5;
export const temperLow = 0.1;
export const temperHigh = 0.9;

export const newTemper: CatTemper = {
  curious: temperStart,
  lazy: temperStart,
  cuddly: temperStart,
};

type Trait = keyof CatTemper;
/** A trait moves `rate` of the way toward `toward` with each such event. */
type Nudge = readonly [trait: Trait, toward: number, rate: number];

const nudgesOf = (event: CatEvent): ReadonlyArray<Nudge> => {
  switch (event._tag) {
    case "Petted":
      return [["cuddly", temperHigh, 0.02]];
    case "NoteShared":
      return [["cuddly", temperHigh, 0.01]];
    case "Played":
      return [
        ["curious", temperHigh, 0.01],
        ["lazy", temperLow, 0.02],
      ];
    case "GamePlayed":
      return [
        ["curious", temperHigh, 0.02],
        ["lazy", temperLow, 0.01],
      ];
    case "Fed":
      return [["lazy", temperHigh, 0.005]];
    case "Watered":
      return [["curious", temperHigh, 0.005]];
    case "Slept":
      return [["lazy", temperHigh, 0.01]];
    case "Shooed":
      return [["cuddly", temperLow, 0.02]];
  }
};

const day = 86_400_000;
/** Each whole day with no entry before this one cools the cat this much, up to a week of days. */
const neglectRate = 0.02;
const neglectDaysMax = 7;

const clamp = (value: number) => Math.min(temperHigh, Math.max(temperLow, value));

const toward = (value: number, target: number, rate: number) =>
  clamp(value + rate * (target - value));

/** The temper after one more journal entry: pure, so every replay gives the same cat. */
export const nextTemper = (
  temper: CatTemper,
  event: CatEvent,
  at: EpochMillis,
  previousAt: EpochMillis | undefined,
): CatTemper => {
  const next = { ...temper };
  if (previousAt !== undefined) {
    const missed = Math.min(neglectDaysMax, Math.floor((at - previousAt) / day));
    for (let i = 0; i < missed; i += 1) next.cuddly = toward(next.cuddly, temperLow, neglectRate);
  }
  for (const [trait, target, rate] of nudgesOf(event)) {
    next[trait] = toward(next[trait], target, rate);
  }
  return next;
};
