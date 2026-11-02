import { Schema } from "effect";
import { MetricEventName } from "@billet/contracts-domain/metrics";
import type { EventRow, FlagRow } from "./funnel.ts";

/** Where to read from. The token should be a Cloudflare API token that can only read D1. */
export interface ReportSource {
  readonly accountId: string;
  readonly databaseId: string;
  readonly apiToken: string;
}

const pageSize = 5_000;
/** A safety stop, so a mistake cannot loop forever. */
const maxPages = 200;

const EventRows = Schema.Array(
  Schema.Struct({
    pair_id: Schema.String,
    user_id: Schema.String,
    name: MetricEventName,
    day: Schema.String,
    count: Schema.Int,
    first_at: Schema.Int,
  }),
);
const FlagRows = Schema.Array(
  Schema.Struct({ pair_id: Schema.String, experiment_key: Schema.String, variant: Schema.String }),
);

const Envelope = Schema.Struct({
  success: Schema.Boolean,
  result: Schema.Array(Schema.Struct({ results: Schema.Array(Schema.Unknown) })),
});
const decodeEnvelope = Schema.decodeUnknownSync(Envelope);

/** The only statements this module sends. Each is one SELECT and nothing else. */
export const statements = {
  events: `SELECT pair_id, user_id, name, day, count, first_at FROM pair_events ORDER BY day, pair_id, user_id, name LIMIT ${pageSize} OFFSET ?`,
  flags: `SELECT pair_id, experiment_key, variant FROM pair_flags ORDER BY pair_id, experiment_key LIMIT ${pageSize} OFFSET ?`,
} as const;

const query = async (
  source: ReportSource,
  sql: string,
  offset: number,
  fetcher: typeof fetch,
): Promise<ReadonlyArray<unknown>> => {
  const response = await fetcher(
    `https://api.cloudflare.com/client/v4/accounts/${source.accountId}/d1/database/${source.databaseId}/query`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${source.apiToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ sql, params: [offset] }),
    },
  );
  // The reason is a status code only: the response body is never printed, it could echo a request.
  if (!response.ok) throw new Error(`D1 query failed with status ${response.status}`);
  const body = decodeEnvelope(await response.json());
  if (!body.success) throw new Error("D1 query was not successful");
  return body.result[0]?.results ?? [];
};

const allPages = async <A>(
  source: ReportSource,
  sql: string,
  decode: (rows: unknown) => ReadonlyArray<A>,
  fetcher: typeof fetch,
): Promise<ReadonlyArray<A>> => {
  const rows: Array<A> = [];
  for (let page = 0; page < maxPages; page += 1) {
    const batch = decode(await query(source, sql, page * pageSize, fetcher));
    rows.push(...batch);
    if (batch.length < pageSize) return rows;
  }
  throw new Error("too many rows to read; narrow the report");
};

/** Reads the counts and the assignments through the Cloudflare API. Read-only by construction. */
export const readRows = async (
  source: ReportSource,
  fetcher: typeof fetch = fetch,
): Promise<{ events: ReadonlyArray<EventRow>; flags: ReadonlyArray<FlagRow> }> => {
  const events = await allPages(
    source,
    statements.events,
    (rows) =>
      Schema.decodeUnknownSync(EventRows)(rows).map((row) => ({
        pairId: row.pair_id,
        userId: row.user_id,
        name: row.name,
        day: row.day,
        count: row.count,
        firstAt: row.first_at,
      })),
    fetcher,
  );
  const flags = await allPages(
    source,
    statements.flags,
    (rows) =>
      Schema.decodeUnknownSync(FlagRows)(rows).map((row) => ({
        pairId: row.pair_id,
        experimentKey: row.experiment_key,
        variant: row.variant,
      })),
    fetcher,
  );
  return { events, flags };
};
