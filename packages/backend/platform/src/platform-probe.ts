import { EpochMillis } from "@billet/contracts-domain/ids";
import { Schema } from "effect";

/**
 * The row of `room_probe`. It gives the platform a table to migrate and query until the room's real
 * tables arrive (#67), which then drop it.
 */
export const PlatformProbe = Schema.Struct({
  id: Schema.String.check(Schema.isNonEmpty()),
  createdAt: EpochMillis,
});
export type PlatformProbe = typeof PlatformProbe.Type;
