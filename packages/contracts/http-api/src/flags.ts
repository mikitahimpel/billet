import { Schema } from "effect";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { AppStatus } from "./status.ts";

/** The variant one experiment gives the caller's pair. Both partners always get the same one. */
export const FlagAssignment = Schema.Struct({ key: ExperimentKey, variant: VariantId });
export type FlagAssignment = typeof FlagAssignment.Type;

/**
 * Unlisted experiments are off. Replace the stored copy, never merge. `status` may be absent.
 */
export const FlagsResponse = Schema.Struct({
  flags: Schema.Array(FlagAssignment),
  status: Schema.optional(AppStatus),
});
export type FlagsResponse = typeof FlagsResponse.Type;
