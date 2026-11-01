import { EpochMillis } from "@billet/contracts-domain/ids";
import { Schema } from "effect";

/**
 * The row of `directory_probe` and `room_probe`. They give the platform a table to migrate and query
 * until the real tables arrive (#14, #15, #67), which then drop them.
 */
export const PlatformProbe = Schema.Struct({
  id: Schema.String.check(Schema.isNonEmpty()),
  createdAt: EpochMillis,
});
export type PlatformProbe = typeof PlatformProbe.Type;
