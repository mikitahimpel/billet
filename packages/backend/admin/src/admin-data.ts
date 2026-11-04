import { Context, Data, type Effect } from "effect";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { EventRow, FlagRow } from "@billet/backend-metrics/funnel";
import type { DetailRow } from "./admin-top-details.ts";

/** A read failed. The panel answers 503; `reason` is a fixed label. */
export class AdminUnavailable extends Data.TaggedError("AdminUnavailable")<{
  readonly reason: string;
}> {}

/**
 * What the panel reads from the directory, besides the flags services. Read-only. It never reads a
 * note, an image, an Apple subject or a push token: counts, pair ids and dates only.
 */
export class AdminData extends Context.Service<
  AdminData,
  {
    /** Every `pair_events` row. The same rows the owner report reads. */
    readonly events: Effect.Effect<ReadonlyArray<EventRow>, AdminUnavailable>;
    /** Every `event_details` row: which cats, items and toys were chosen, apart from anyone. */
    readonly details: Effect.Effect<ReadonlyArray<DetailRow>, AdminUnavailable>;
    /** Every `pair_flags` row. */
    readonly assignments: Effect.Effect<ReadonlyArray<FlagRow>, AdminUnavailable>;
    readonly userCount: Effect.Effect<number, AdminUnavailable>;
    /** How many accounts are in the pair now, and when the first joined it. */
    readonly pair: (
      pairId: PairId,
    ) => Effect.Effect<
      { readonly members: number; readonly pairedAt: number | null },
      AdminUnavailable
    >;
  }
>()("@billet/backend-admin/AdminData") {}
