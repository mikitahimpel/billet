import { Data } from "effect";

/** The code is unknown, expired, already claimed or the caller's own: the client can't tell which. */
export class InvalidInvite extends Data.TaggedError("InvalidInvite") {}

/** The caller already has a partner, and has to unpair first. */
export class AlreadyPaired extends Data.TaggedError("AlreadyPaired") {}

/** A dependency failed, so nothing changed. The client can retry; `reason` is a fixed label. */
export class PairingUnavailable extends Data.TaggedError("PairingUnavailable")<{
  readonly reason: string;
}> {}
