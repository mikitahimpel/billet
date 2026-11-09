import { Context, Data, Effect, Layer, Option } from "effect";
import type { EngineRow, TrendQuery } from "./admin-trends.ts";

/** Analytics Engine could not be read. `reason` is a fixed label; the panel falls back to D1. */
export class EngineUnavailable extends Data.TaggedError("EngineUnavailable")<{
  readonly reason: string;
  readonly cause?: unknown;
}> {}

/** One SELECT, read-only. `none` when the Worker has no read token: the panel uses D1 alone. */
export class AnalyticsEngineReader extends Context.Service<
  AnalyticsEngineReader,
  {
    readonly trend: (
      query: TrendQuery,
      from: string,
      today: string,
    ) => Effect.Effect<Option.Option<ReadonlyArray<EngineRow>>, EngineUnavailable>;
  }
>()("@billet/backend-admin/AnalyticsEngineReader") {
  /** No Analytics Engine: every trend comes from D1. */
  static readonly none = Layer.succeed(AnalyticsEngineReader, {
    trend: () => Effect.succeed(Option.none()),
  });
}
