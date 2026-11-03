import { Schema } from "effect";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { AppStatus } from "./status.ts";

/** The variant one experiment gives the caller's pair. Both partners always get the same one. */
export const FlagAssignment = Schema.Struct({ key: ExperimentKey, variant: VariantId });
export type FlagAssignment = typeof FlagAssignment.Type;

/**
 * Every running experiment and the variant the pair is in. An experiment that is not listed is off
 * (not started, or switched off), and a client uses its built-in default. A client replaces its
 * stored copy with this list, never merges into it, so switching an experiment off takes effect.
 *
 * `status` is the service status (`GET /v1/status`), next to the flags so one launch read gets
 * both. Optional: an older server leaves it out, and an older app ignores it.
 */
export const FlagsResponse = Schema.Struct({
  flags: Schema.Array(FlagAssignment),
  status: Schema.optional(AppStatus),
});
export type FlagsResponse = typeof FlagsResponse.Type;
