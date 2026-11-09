import { addDays } from "@billet/backend-metrics/funnel";
import type { DetailRow } from "./admin-top-details.ts";

/** What one arm did with one hint. A rate is left out under `minShown` hints: too few to read. */
export interface HintArm {
  readonly shown: number;
  readonly dismissed: number;
  readonly acted: number;
  readonly actedRate: number | null;
}

/** One hint: the pairs that saw it against the holdout, which reports the hints it would have had. */
export interface HintRate {
  readonly hint: string;
  readonly show: HintArm;
  readonly hold: HintArm;
  /** Difference of the acted rates, show minus hold; null when either is unreadable. */
  readonly lift: number | null;
}

export const minShown = 5;

const holdSuffix = "-hold";

const arm = (shown: number, dismissed: number, acted: number): HintArm => ({
  shown,
  dismissed,
  acted,
  actedRate: shown < minShown ? null : acted / shown,
});

/**
 * Shown-to-acted rates against the `hints` holdout, which reports `<id>-hold`. Rows hold no pair.
 */
export const buildHintRates = (
  details: ReadonlyArray<DetailRow>,
  today: string,
  days = 30,
): ReadonlyArray<HintRate> => {
  const from = addDays(today, 1 - days);
  const counts = new Map<string, number>();
  for (const row of details) {
    if (row.day < from || row.day > today) continue;
    if (row.name !== "TipShown" && row.name !== "TipDismissed" && row.name !== "TipAction")
      continue;
    const key = `${row.name}|${row.detail}`;
    counts.set(key, (counts.get(key) ?? 0) + row.count);
  }
  const hints = new Set<string>();
  for (const key of counts.keys()) {
    const detail = key.slice(key.indexOf("|") + 1);
    hints.add(detail.endsWith(holdSuffix) ? detail.slice(0, -holdSuffix.length) : detail);
  }
  const of = (name: string, detail: string) => counts.get(`${name}|${detail}`) ?? 0;
  return [...hints].toSorted().map((hint) => {
    const show = arm(of("TipShown", hint), of("TipDismissed", hint), of("TipAction", hint));
    const held = `${hint}${holdSuffix}`;
    const hold = arm(of("TipShown", held), of("TipDismissed", held), of("TipAction", held));
    return {
      hint,
      show,
      hold,
      lift:
        show.actedRate === null || hold.actedRate === null ? null : show.actedRate - hold.actedRate,
    };
  });
};
