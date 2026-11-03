import { Schema } from "effect";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { EpochMillis } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { defineExperiment, type Experiment, ExperimentStatus, Targeting } from "./experiments.ts";

/**
 * The part of an experiment the admin may change without a deploy. The key, kind and variant ids
 * are not here: they are fixed by the registry, because the app must contain every variant.
 */
export const FlagConfig = Schema.Struct({
  description: Schema.String.check(Schema.isMaxLength(500)),
  /** Every variant id of the registry entry, each with a whole-number weight of 0 or more. */
  weights: Schema.Record(VariantId, Schema.Int.check(Schema.isGreaterThanOrEqualTo(0))),
  default: VariantId,
  exposure: Schema.Int.check(Schema.isBetween({ minimum: 0, maximum: 100 })),
  status: ExperimentStatus,
  killed: Schema.Boolean,
  targeting: Targeting,
});
export type FlagConfig = typeof FlagConfig.Type;

/** A `flag_configs` row: the live configuration of one registry entry. */
export const StoredFlagConfig = Schema.Struct({
  key: ExperimentKey,
  config: FlagConfig,
  /** Starts at 1 and goes up by one per save, so two editors cannot overwrite each other. */
  version: Schema.Int,
  updatedAt: EpochMillis,
  /** The Cloudflare Access identity (email) of whoever saved it. */
  updatedBy: Schema.String,
});
export type StoredFlagConfig = typeof StoredFlagConfig.Type;

export const FlagChangeAction = Schema.Literals([
  "edit",
  "start",
  "stop",
  "kill",
  "unkill",
  "override",
  "clear-override",
]);
export type FlagChangeAction = typeof FlagChangeAction.Type;

/** One line of the history: who changed what, and the configuration before and after. */
export const FlagChange = Schema.Struct({
  id: Schema.Int,
  key: ExperimentKey,
  at: EpochMillis,
  by: Schema.String,
  action: FlagChangeAction,
  /** For an override: the pair it is for. */
  pairId: Schema.optional(PairId),
  before: Schema.NullOr(Schema.Unknown),
  after: Schema.NullOr(Schema.Unknown),
});
export type FlagChange = typeof FlagChange.Type;

/** A variant forced on one pair, for testing on the owner's own phones. */
export const PairOverride = Schema.Struct({
  pairId: PairId,
  experimentKey: ExperimentKey,
  variant: VariantId,
  setAt: EpochMillis,
  setBy: Schema.String,
});
export type PairOverride = typeof PairOverride.Type;

/** The configuration a registry entry starts with, before anyone edits it. */
export const configOf = (experiment: Experiment): FlagConfig => ({
  description: experiment.description,
  weights: Object.fromEntries(experiment.variants.map(({ id, weight }) => [id, weight])),
  default: experiment.default,
  exposure: experiment.exposure,
  status: experiment.status,
  killed: experiment.killed,
  targeting: experiment.targeting,
});

/**
 * The registry entry with `config` applied, or why it can't be. The config must weigh exactly the
 * entry's variants, so it can neither add a variant the app lacks nor drop one.
 */
export const applyConfig = (
  entry: Experiment,
  config: FlagConfig,
): { readonly experiment: Experiment } | { readonly error: string } => {
  const ids = entry.variants.map(({ id }) => id as string);
  const given = Object.keys(config.weights);
  const unknown = given.filter((id) => !ids.includes(id));
  if (unknown.length > 0) return { error: `unknown variants: ${unknown.join(", ")}` };
  const missing = ids.filter((id) => !given.includes(id));
  if (missing.length > 0) return { error: `missing variants: ${missing.join(", ")}` };
  try {
    return {
      experiment: defineExperiment({
        key: entry.key,
        kind: entry.kind,
        description: config.description,
        // Registry order, so assignment walks the variants the same way whatever the JSON order.
        variants: Object.fromEntries(ids.map((id) => [id, config.weights[id as VariantId] ?? 0])),
        default: config.default,
        exposure: config.exposure,
        status: config.status,
        killed: config.killed,
        targeting: config.targeting,
      }),
    };
  } catch (error) {
    return { error: error instanceof Error ? error.message : "invalid configuration" };
  }
};

/**
 * The registry with each stored configuration applied. A stored row for a key the registry does
 * not have is ignored, and so is one that no longer fits its entry (a variant removed in code):
 * that entry keeps its registry configuration.
 */
export const effectiveExperiments = (
  registry: ReadonlyArray<Experiment>,
  stored: ReadonlyArray<StoredFlagConfig>,
): ReadonlyArray<Experiment> => {
  const byKey = new Map(stored.map((row) => [row.key, row.config]));
  return registry.map((entry) => {
    const config = byKey.get(entry.key);
    if (config === undefined) return entry;
    const applied = applyConfig(entry, config);
    return "experiment" in applied ? applied.experiment : entry;
  });
};
