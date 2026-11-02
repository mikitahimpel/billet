import { Context, Layer, Schema } from "effect";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";

/**
 * One question asked of real pairs. The unit is the pair, so both partners always see the same
 * variant. Every variant must already be built into the app: assignment only picks between
 * variants a reviewed build contains, and never turns on code that App Review has not seen.
 */
export interface Experiment {
  readonly key: ExperimentKey;
  /** Variants in a fixed order, with a whole-number weight each. The default is one of them. */
  readonly variants: ReadonlyArray<{ readonly id: VariantId; readonly weight: number }>;
  /** What a pair gets when it is outside the experiment, when the experiment is off and offline. */
  readonly default: VariantId;
  /** Whole percent of pairs that enter the experiment. The rest keep the default and are not analysed. */
  readonly exposure: number;
  /** On: the server stops delivering the experiment and every client falls back to its default. */
  readonly killed: boolean;
}

export interface ExperimentSpec {
  readonly key: string;
  /** Variant id to weight. At least two. The order here is the order assignment walks. */
  readonly variants: Readonly<Record<string, number>>;
  readonly default: string;
  readonly exposure: number;
  readonly killed: boolean;
}

const decodeKey = Schema.decodeSync(ExperimentKey);
const decodeVariant = Schema.decodeSync(VariantId);

/** Checks a spec and fills in the types. Throws on a mistake, so a bad registry fails at start-up. */
export const defineExperiment = (spec: ExperimentSpec): Experiment => {
  const entries = Object.entries(spec.variants);
  if (entries.length < 2) throw new Error(`${spec.key}: an experiment needs at least two variants`);
  for (const [id, weight] of entries) {
    if (!Number.isInteger(weight) || weight < 1) {
      throw new Error(`${spec.key}: the weight of ${id} must be a whole number of 1 or more`);
    }
  }
  if (!(spec.default in spec.variants)) {
    throw new Error(`${spec.key}: the default ${spec.default} is not one of its variants`);
  }
  if (!Number.isInteger(spec.exposure) || spec.exposure < 0 || spec.exposure > 100) {
    throw new Error(`${spec.key}: exposure is a whole percent from 0 to 100`);
  }
  return {
    key: decodeKey(spec.key),
    variants: entries.map(([id, weight]) => ({ id: decodeVariant(id), weight })),
    default: decodeVariant(spec.default),
    exposure: spec.exposure,
    killed: spec.killed,
  };
};

/** A list of experiments with unique keys. */
export const defineExperiments = (
  specs: ReadonlyArray<ExperimentSpec>,
): ReadonlyArray<Experiment> => {
  const experiments = specs.map(defineExperiment);
  const keys = new Set(experiments.map(({ key }) => key));
  if (keys.size !== experiments.length) throw new Error("two experiments share a key");
  return experiments;
};

/**
 * Every experiment this server knows. Adding one is a change to this list and the matching
 * variants in the app: see docs/experiments.md. An experiment stays here, killed, after it ends,
 * so its key is never reused for another question.
 */
export const registry: ReadonlyArray<Experiment> = defineExperiments([
  // The first planned test (decisions.md, 2026-11-02). Off until the owner starts it.
  {
    key: "home-direction",
    variants: { "window-seat": 50, "sunset-lamp": 50 },
    default: "window-seat",
    exposure: 100,
    killed: true,
  },
]);

/** The experiments a `FlagsService` works from. Tests supply their own. */
export class Experiments extends Context.Service<Experiments, ReadonlyArray<Experiment>>()(
  "@billet/backend-flags/Experiments",
) {
  static readonly live = Layer.succeed(Experiments, registry);
  static readonly with = (experiments: ReadonlyArray<Experiment>) =>
    Layer.succeed(Experiments, experiments);
}
