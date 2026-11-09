// Not `Cloudflare.state()`: that needs the account's Secrets Store, which the deploy token cannot
// reach. The database is outside the stack, so `alchemy destroy` keeps it. Rows hold Worker
// secrets in plaintext, readable with the deploy token, as its Workers access already allows.
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as HttpClient from "effect/http/HttpClient";
import * as HttpClientRequest from "effect/http/HttpClientRequest";
import * as Layer from "effect/Layer";
import * as Redacted from "effect/Redacted";
import {
  encodeState,
  reviveState,
  State,
  STATE_STORE_VERSION,
  StateStoreError,
  type PersistedState,
  type StateService,
} from "alchemy/State";

interface D1StateOptions {
  /** Name of the D1 database that holds the state, created when missing. */
  readonly databaseName: string;
}

export const d1State = (options: D1StateOptions) =>
  Layer.effect(
    State,
    Effect.gen(function* () {
      const context = yield* Effect.context<HttpClient.HttpClient>();
      // Like `Cloudflare.state()`, a store that cannot start fails the run.
      return yield* Effect.cached(
        makeD1State(options).pipe(Effect.provideContext(context), Effect.orDie),
      );
    }),
  );

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS resources (stack TEXT NOT NULL, stage TEXT NOT NULL, fqn TEXT NOT NULL,
    value TEXT NOT NULL, PRIMARY KEY (stack, stage, fqn))`,
  `CREATE TABLE IF NOT EXISTS outputs (stack TEXT NOT NULL, stage TEXT NOT NULL,
    value TEXT NOT NULL, PRIMARY KEY (stack, stage))`,
];

const makeD1State = ({ databaseName }: D1StateOptions) =>
  Effect.gen(function* () {
    const accountId = yield* Config.String("CLOUDFLARE_ACCOUNT_ID");
    const apiToken = yield* Config.Redacted("CLOUDFLARE_API_TOKEN");
    const client = yield* HttpClient.HttpClient;
    const base = `https://api.cloudflare.com/client/v4/accounts/${accountId}/d1/database`;

    // Error messages never carry the account id, the token or a response body.
    const fail = (message: string, cause?: unknown) =>
      new StateStoreError({
        message: `D1 state store '${databaseName}': ${message}`,
        ...(cause instanceof Error
          ? { cause: new Error(cause.message.replaceAll(accountId, "<account>")) }
          : {}),
      });

    const call = (request: HttpClientRequest.HttpClientRequest) =>
      client.execute(request.pipe(HttpClientRequest.bearerToken(Redacted.value(apiToken)))).pipe(
        Effect.flatMap((response) => response.json),
        Effect.mapError((cause) => fail("Cloudflare API request failed", cause)),
        Effect.flatMap((body) => {
          const envelope = body as { success?: boolean; result?: unknown; errors?: unknown };
          return envelope.success === true
            ? Effect.succeed(envelope.result)
            : Effect.fail(fail(`Cloudflare API error ${JSON.stringify(envelope.errors ?? null)}`));
        }),
      );

    const found = (yield* call(
      HttpClientRequest.get(base).pipe(HttpClientRequest.setUrlParam("name", databaseName)),
    )) as ReadonlyArray<{ name: string; uuid: string }>;
    const databaseId =
      found.find((db) => db.name === databaseName)?.uuid ??
      (
        (yield* call(
          HttpClientRequest.post(base).pipe(
            HttpClientRequest.bodyJsonUnsafe({ name: databaseName }),
          ),
        )) as { uuid: string }
      ).uuid;

    const query = (sql: string, params: ReadonlyArray<string> = []) =>
      call(
        HttpClientRequest.post(`${base}/${databaseId}/query`).pipe(
          HttpClientRequest.bodyJsonUnsafe({ sql, params }),
        ),
      ).pipe(
        Effect.map(
          (result) =>
            ((result as ReadonlyArray<{ results: ReadonlyArray<Record<string, string>> }>)[0]
              ?.results ?? []) as ReadonlyArray<Record<string, string>>,
        ),
      );

    for (const statement of SCHEMA) yield* query(statement);

    const encode = (value: unknown) => JSON.stringify(encodeState(value));
    const decode = (text: string | undefined) =>
      text === undefined
        ? Effect.succeed(undefined)
        : Effect.try({
            try: () => JSON.parse(text, reviveState),
            catch: (cause) => fail("unreadable state row", cause),
          });

    const state: StateService = {
      id: "cloudflare-d1",
      getVersion: () => Effect.succeed(STATE_STORE_VERSION),
      listStacks: () =>
        query("SELECT DISTINCT stack FROM resources ORDER BY stack").pipe(
          Effect.map((rows) => rows.map((row) => row.stack!)),
        ),
      listStages: (stack) =>
        query("SELECT DISTINCT stage FROM resources WHERE stack = ? ORDER BY stage", [stack]).pipe(
          Effect.map((rows) => rows.map((row) => row.stage!)),
        ),
      get: ({ stack, stage, fqn }) =>
        query("SELECT value FROM resources WHERE stack = ? AND stage = ? AND fqn = ?", [
          stack,
          stage,
          fqn,
        ]).pipe(
          Effect.flatMap(
            (rows) =>
              decode(rows[0]?.value) as Effect.Effect<PersistedState | undefined, StateStoreError>,
          ),
        ),
      getReplacedResources: ({ stack, stage }) =>
        query("SELECT value FROM resources WHERE stack = ? AND stage = ?", [stack, stage]).pipe(
          Effect.flatMap((rows) => Effect.forEach(rows, (row) => decode(row.value))),
          Effect.map((values) => values.filter((value) => value?.status === "replaced")),
        ),
      set: ({ stack, stage, fqn, value }) =>
        query(
          `INSERT INTO resources (stack, stage, fqn, value) VALUES (?, ?, ?, ?)
            ON CONFLICT (stack, stage, fqn) DO UPDATE SET value = excluded.value`,
          [stack, stage, fqn, encode(value)],
        ).pipe(Effect.as(value)),
      delete: ({ stack, stage, fqn }) =>
        query("DELETE FROM resources WHERE stack = ? AND stage = ? AND fqn = ?", [
          stack,
          stage,
          fqn,
        ]).pipe(Effect.asVoid),
      deleteStack: ({ stack, stage }) =>
        Effect.forEach(["resources", "outputs"], (table) =>
          stage === undefined
            ? query(`DELETE FROM ${table} WHERE stack = ?`, [stack])
            : query(`DELETE FROM ${table} WHERE stack = ? AND stage = ?`, [stack, stage]),
        ).pipe(Effect.asVoid),
      list: ({ stack, stage }) =>
        query("SELECT fqn FROM resources WHERE stack = ? AND stage = ? ORDER BY fqn", [
          stack,
          stage,
        ]).pipe(Effect.map((rows) => rows.map((row) => row.fqn!))),
      getOutput: ({ stack, stage }) =>
        query("SELECT value FROM outputs WHERE stack = ? AND stage = ?", [stack, stage]).pipe(
          Effect.flatMap((rows) => decode(rows[0]?.value)),
        ),
      setOutput: ({ stack, stage, value }) =>
        query(
          `INSERT INTO outputs (stack, stage, value) VALUES (?, ?, ?)
            ON CONFLICT (stack, stage) DO UPDATE SET value = excluded.value`,
          [stack, stage, encode(value)],
        ).pipe(Effect.as(value)),
    };
    return state;
  });
