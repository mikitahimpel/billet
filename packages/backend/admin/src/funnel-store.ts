import { Context, Data, type Effect } from "effect";
import type { FunnelDefinition } from "./admin-funnel.ts";

/** A funnel the owner saved, with who saved it. */
export interface SavedFunnel {
  readonly id: string;
  readonly name: string;
  readonly definition: FunnelDefinition;
  readonly createdAt: number;
  readonly createdBy: string;
}

/** The store could not be read or written. `reason` is a fixed label. */
export class FunnelStoreUnavailable extends Data.TaggedError("FunnelStoreUnavailable")<{
  readonly reason: string;
  /** What failed underneath, for the one log line at the edge. Never sent to the client. */
  readonly cause?: unknown;
}> {}

/** Saved funnels: definitions only, never a count or anything about a pair. */
export class FunnelStore extends Context.Service<
  FunnelStore,
  {
    /** Every saved funnel, newest first. */
    readonly all: Effect.Effect<ReadonlyArray<SavedFunnel>, FunnelStoreUnavailable>;
    readonly save: (funnel: SavedFunnel) => Effect.Effect<void, FunnelStoreUnavailable>;
    /** Removes it; true when there was one. */
    readonly remove: (id: string) => Effect.Effect<boolean, FunnelStoreUnavailable>;
  }
>()("@billet/backend-admin/FunnelStore") {}
