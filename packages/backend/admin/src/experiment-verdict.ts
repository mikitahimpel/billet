import { minimumPairsPerVariant, type VariantReport } from "@billet/backend-metrics/funnel";

export interface Verdict {
  /**
   * `no-data`: under two variants at day 7; `overlap`: intervals touch; `ahead`: one sits above.
   */
  readonly kind: "no-data" | "overlap" | "ahead";
  /** The variant that is ahead, for `ahead`. */
  readonly leader: string | null;
  /** True while the smallest variant has fewer than `minimumPairsPerVariant` pairs at day 7. */
  readonly small: boolean;
  /** One plain sentence for the owner. */
  readonly text: string;
}

/** A variant is only called ahead when its 95% interval overlaps no other's. */
export const verdictOf = (variants: ReadonlyArray<VariantReport>): Verdict => {
  const measured = variants.filter(({ northStar }) => northStar.interval !== undefined);
  const smallest = Math.min(...variants.map(({ northStar }) => northStar.of));
  const small = !Number.isFinite(smallest) || smallest < minimumPairsPerVariant;
  if (measured.length < 2) {
    return {
      kind: "no-data",
      leader: null,
      small: true,
      text: "Not enough data yet: fewer than two variants have a pair that reached day 7.",
    };
  }
  const best = measured.toSorted((a, b) => (b.northStar.share ?? 0) - (a.northStar.share ?? 0))[0];
  const clear =
    best !== undefined &&
    measured.every(
      (other) =>
        other === best ||
        (best.northStar.interval?.low ?? 0) > (other.northStar.interval?.high ?? 1),
    );
  if (best !== undefined && clear) {
    return {
      kind: "ahead",
      leader: best.variant,
      small,
      text: small
        ? `${best.variant} looks better: its 95% interval doesn't overlap the others', but the smallest variant has only ${smallest} pairs at day 7, so check again before acting.`
        : `${best.variant} looks better: its 95% interval doesn't overlap the others'.`,
    };
  }
  return {
    kind: "overlap",
    leader: null,
    small,
    text: small
      ? `Not enough data yet: the 95% intervals overlap and the smallest variant has ${smallest} of the ${minimumPairsPerVariant} pairs at day 7 worth reading.`
      : "No difference yet: the 95% intervals overlap.",
  };
};
