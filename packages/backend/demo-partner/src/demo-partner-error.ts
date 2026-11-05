import { Data } from "effect";

/** The caller has no demo partner. */
export class NoDemoPartner extends Data.TaggedError("NoDemoPartner") {}

/** A dependency failed. The client can retry; `reason` is a fixed label. */
export class DemoPartnerUnavailable extends Data.TaggedError("DemoPartnerUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}
