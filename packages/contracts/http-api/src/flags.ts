import { Schema } from "effect";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";

/** The variant one experiment gives the caller's pair. Both partners always get the same one. */
export const FlagAssignment = Schema.Struct({ key: ExperimentKey, variant: VariantId });
export type FlagAssignment = typeof FlagAssignment.Type;

/**
 * Every running experiment and the variant the pair is in. An experiment that is not listed is off
 * (not started, or switched off), and a client uses its built-in default. A client replaces its
 * stored copy with this list, never merges into it, so switching an experiment off takes effect.
 */
export const FlagsResponse = Schema.Struct({ flags: Schema.Array(FlagAssignment) });
export type FlagsResponse = typeof FlagsResponse.Type;
