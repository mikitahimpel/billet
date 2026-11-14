import { Effect, Layer, Option, Schema } from "effect";
import { engineSql } from "@billet/backend-admin/admin-trends";
import {
  AnalyticsEngineReader,
  EngineUnavailable,
} from "@billet/backend-admin/analytics-engine-reader";

/** The token can only read Account Analytics. */
export interface EngineReadConfig {
  readonly accountId: string;
  readonly token: string;
  readonly stage: string;
  /** The stack name in front of `_<stage>_events`; absent, `billet`. */
  readonly stack: string;
}

// The SQL API sends 64-bit numbers as strings.
const Num = Schema.Union([Schema.Number, Schema.NumberFromString]);
const Answer = Schema.Struct({
  data: Schema.Array(
    Schema.Struct({
      day: Schema.String,
      grp: Schema.String,
      count: Num,
      hashes: Num,
      unpaired: Num,
    }),
  ),
});
const decodeAnswer = Schema.decodeUnknownEffect(Answer);

/** Without an account id, token or stage it is `none`. A failure body is never logged. */
export const AnalyticsEngineReaderLive = (
  config: { readonly [K in keyof EngineReadConfig]?: string | undefined },
  fetcher: typeof fetch = fetch,
): Layer.Layer<AnalyticsEngineReader> => {
  const { accountId, token, stage } = config;
  const stack = config.stack || "billet";
  if (
    !accountId ||
    !token ||
    !stage ||
    !/^[a-z0-9]+$/.test(stage) ||
    !/^[a-z][a-z0-9]*$/.test(stack) ||
    !/^[0-9a-f]{32}$/.test(accountId)
  )
    return AnalyticsEngineReader.none;
  return Layer.succeed(AnalyticsEngineReader, {
    trend: (query, from, today) =>
      Effect.gen(function* () {
        const sql = yield* Effect.try({
          try: () => engineSql(`${stack}_${stage}_events`, query, from, today),
          catch: (cause) => new EngineUnavailable({ reason: "bad-query", cause }),
        });
        const response = yield* Effect.tryPromise({
          try: () =>
            fetcher(
              `https://api.cloudflare.com/client/v4/accounts/${accountId}/analytics_engine/sql`,
              { method: "POST", headers: { authorization: `Bearer ${token}` }, body: sql },
            ),
          catch: (cause) => new EngineUnavailable({ reason: "unreachable", cause }),
        });
        if (!response.ok) {
          return yield* new EngineUnavailable({ reason: `status-${response.status}` });
        }
        const body = yield* Effect.tryPromise({
          try: () => response.json() as Promise<unknown>,
          catch: (cause) => new EngineUnavailable({ reason: "not-json", cause }),
        });
        const answer = yield* decodeAnswer(body).pipe(
          Effect.mapError((cause) => new EngineUnavailable({ reason: "unexpected-answer", cause })),
        );
        return Option.some(
          answer.data.map((row) => ({
            day: row.day.slice(0, 10),
            group: row.grp,
            count: row.count,
            pairs: row.hashes - (row.unpaired > 0 ? 1 : 0),
          })),
        );
      }),
  });
};
