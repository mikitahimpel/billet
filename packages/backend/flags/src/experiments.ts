import { Context, Layer, Schema } from "effect";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { PairId } from "@billet/contracts-domain/pair-id";

/**
 * - `draft`: delivered to nobody but pairs with an override, so the owner can try it first.
 * - `running`: pairs enter as they read their flags, and keep what they were given.
 * - `stopped`: nobody new enters; pairs already in keep their variant, so a test can finish.
 */
export const ExperimentStatus = Schema.Literals(["draft", "running", "stopped"]);
export type ExperimentStatus = typeof ExperimentStatus.Type;

/**
 * - `experiment`: a question with one primary metric, compared variant against variant.
 * - `flag`: a Labs setting the owner can roll out remotely. Same delivery, no comparison.
 */
export const ExperimentKind = Schema.Literals(["experiment", "flag"]);
export type ExperimentKind = typeof ExperimentKind.Type;

/** The age bands pairing allows (decisions.md, 2026-11-02): 13–17 with 13–17, 18+ with 18+. */
export const AgeBand = Schema.Literals(["13-17", "18+"]);
export type AgeBand = typeof AgeBand.Type;

/** `<marketing>` or `<marketing>+<build>`, as the app sends it: `1.2`, `1.2.0+14`. */
export const AppVersionBound = Schema.String.check(
  Schema.isPattern(/^\d{1,4}(\.\d{1,4}){0,3}(\+\d{1,8})?$/),
);

/**
 * Who may enter. Every rule left out lets everyone through; every rule given must hold. A pair the
 * rules leave out is not listed at all, so its app keeps its built-in default.
 */
export const Targeting = Schema.Struct({
  /** Inclusive. A build that sent no version is left out by either bound. */
  minAppVersion: Schema.optional(AppVersionBound),
  maxAppVersion: Schema.optional(AppVersionBound),
  /** Pairs whose band is known and listed. Empty or absent: every pair, known band or not. */
  ageBands: Schema.optional(Schema.Array(AgeBand)),
  /** Only these pairs, for a test on the owner's own pair. Empty or absent: every pair. */
  pairIds: Schema.optional(Schema.Array(PairId).check(Schema.isMaxLength(200))),
});
export type Targeting = typeof Targeting.Type;

/**
 * One question asked of real pairs, or one setting rolled out to them. The unit is the pair, so
 * both partners always see the same variant. Every variant must already be built into the app:
 * assignment only picks between variants a reviewed build contains, and never turns on code that
 * App Review has not seen.
 */
export interface Experiment {
  readonly key: ExperimentKey;
  readonly kind: ExperimentKind;
  /** One or two plain sentences: what it changes, and for an experiment its primary metric. */
  readonly description: string;
  /** Variants in a fixed order, with a whole-number weight each. The default is one of them. */
  readonly variants: ReadonlyArray<{ readonly id: VariantId; readonly weight: number }>;
  /** What a pair gets when it is inside the targeting but outside the exposure. */
  readonly default: VariantId;
  /** Whole percent of targeted pairs that enter. The rest get the default and are not analysed. */
  readonly exposure: number;
  readonly status: ExperimentStatus;
  /** On: the server stops delivering it to anyone, overrides included; every app falls back. */
  readonly killed: boolean;
  readonly targeting: Targeting;
}

export interface ExperimentSpec {
  readonly key: string;
  readonly kind?: ExperimentKind;
  readonly description?: string;
  /** Variant id to weight. At least two. The order here is the order assignment walks. */
  readonly variants: Readonly<Record<string, number>>;
  readonly default: string;
  readonly exposure: number;
  /** `running` when left out. */
  readonly status?: ExperimentStatus;
  readonly killed: boolean;
  readonly targeting?: Targeting;
}

const decodeKey = Schema.decodeSync(ExperimentKey);
const decodeVariant = Schema.decodeSync(VariantId);
const decodeTargeting = Schema.decodeUnknownSync(Targeting);

/** Checks a spec and fills in the types. Throws on a mistake, so a bad registry fails at start-up. */
export const defineExperiment = (spec: ExperimentSpec): Experiment => {
  const entries = Object.entries(spec.variants);
  if (entries.length < 2) throw new Error(`${spec.key}: an experiment needs at least two variants`);
  for (const [id, weight] of entries) {
    if (!Number.isInteger(weight) || weight < 0) {
      throw new Error(`${spec.key}: the weight of ${id} must be a whole number of 0 or more`);
    }
  }
  if (entries.every(([, weight]) => weight === 0)) {
    throw new Error(`${spec.key}: at least one variant needs a weight above 0`);
  }
  if (!(spec.default in spec.variants)) {
    throw new Error(`${spec.key}: the default ${spec.default} is not one of its variants`);
  }
  if (!Number.isInteger(spec.exposure) || spec.exposure < 0 || spec.exposure > 100) {
    throw new Error(`${spec.key}: exposure is a whole percent from 0 to 100`);
  }
  if ((spec.description ?? "").length > 500) {
    throw new Error(`${spec.key}: the description is over 500 characters`);
  }
  return {
    key: decodeKey(spec.key),
    kind: spec.kind ?? "experiment",
    description: spec.description ?? "",
    variants: entries.map(([id, weight]) => ({ id: decodeVariant(id), weight })),
    default: decodeVariant(spec.default),
    exposure: spec.exposure,
    status: spec.status ?? "running",
    killed: spec.killed,
    targeting: decodeTargeting(spec.targeting ?? {}),
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
 * Every experiment and remote flag this server knows: the one place they are defined. The key,
 * kind and variant ids here are fixed, because they must match what the app contains
 * (`Experiments` in packages/ios/Sources/WidgetBridge/RemoteFlags.swift, checked by a Swift test
 * that reads this file). Everything else here is only the starting configuration: the admin
 * panel changes weights, default, exposure, status, kill switch and targeting without a deploy,
 * and stores them in D1 (`flag_configs`). See docs/experiments.md and docs/admin.md.
 *
 * An entry stays here after it ends, so its key is never reused for another question.
 * Variant ids are the app's case names in kebab-case.
 */
export const registry: ReadonlyArray<Experiment> = defineExperiments([
  // Labs settings the owner can roll out remotely. Each is a complete, reviewed choice in the
  // app; a Labs choice on the phone still wins. Draft: nothing changes until the owner starts one.
  {
    key: "room-lighting",
    kind: "flag",
    description: "How the rooms are lit (Labs > Lighting).",
    variants: {
      "amber-lantern": 1,
      off: 0,
      "fairy-lights": 0,
      "golden-hour": 0,
      "neon-night": 0,
      candle: 0,
    },
    default: "amber-lantern",
    exposure: 100,
    status: "draft",
    killed: false,
  },
  {
    key: "window-view",
    kind: "flag",
    description: "What the room's window looks out on (Labs > Window view).",
    variants: {
      "suburb-night": 1,
      "rainy-suburb": 0,
      "snowy-december": 0,
      "summer-cul-de-sac": 0,
      "dorm-quad": 0,
      "fire-escape": 0,
      "pink-dusk": 0,
    },
    default: "suburb-night",
    exposure: 100,
    status: "draft",
    killed: false,
  },
  {
    key: "home-layout",
    kind: "flag",
    description: "How Home is laid out around the room (Labs > Home).",
    variants: {
      classic: 1,
      immersive: 0,
      "living-window": 0,
      "night-and-day": 0,
    },
    default: "classic",
    exposure: 100,
    status: "draft",
    killed: false,
  },
  {
    key: "shopkeeper",
    kind: "flag",
    description: "Who keeps the 3D shop (Labs > Shopkeeper).",
    variants: { teddy: 1, human: 0 },
    default: "teddy",
    exposure: 100,
    status: "draft",
    killed: false,
  },
]);

/** The catalogue a `FlagsService` works from: the registry, or what a test supplies. */
export class Experiments extends Context.Service<Experiments, ReadonlyArray<Experiment>>()(
  "@billet/backend-flags/Experiments",
) {
  static readonly live = Layer.succeed(Experiments, registry);
  static readonly with = (experiments: ReadonlyArray<Experiment>) =>
    Layer.succeed(Experiments, experiments);
}
