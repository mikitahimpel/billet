import { Clock, Context, Data, Effect, Layer, Schema } from "effect";
import { Digest } from "effect/crypto";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { PairId } from "@billet/contracts-domain/pair-id";
import { Experiments, type Experiment } from "@billet/backend-flags/experiments";
import {
  applyConfig,
  configOf,
  FlagConfig,
  type FlagChangeAction,
  type StoredFlagConfig,
} from "@billet/backend-flags/flag-config";
import { FlagConfigRepository } from "@billet/backend-flags/flag-config-repository";
import { FlagsRepository } from "@billet/backend-flags/flags-repository";
import { FlagsService } from "@billet/backend-flags/flags-service";
import { pairHashOf } from "@billet/backend-metrics/analytics";
import { buildReport } from "@billet/backend-metrics/funnel";
import { utcDay } from "@billet/backend-metrics/metrics";
import { AppStatus } from "@billet/contracts-http-api/status";
import type { AdminIdentity } from "./access.ts";
import { AdminData } from "./admin-data.ts";
import { buildAppEvents } from "./admin-app-events.ts";
import { buildOverview } from "./admin-overview.ts";
import { AppStatusStore } from "./app-status-store.ts";
import { verdictOf } from "./experiment-verdict.ts";

/** Who is using the panel, as Cloudflare Access verified them. Every change is logged under it. */
export class CurrentAdmin extends Context.Service<CurrentAdmin, AdminIdentity>()(
  "@billet/backend-admin/CurrentAdmin",
) {}

/**
 * Which deployment the panel belongs to (the Alchemy stage: `dev`, `prod`), shown in its top bar
 * so a change is never made on the wrong one by mistake.
 */
export class PanelEnvironment extends Context.Service<
  PanelEnvironment,
  { readonly name: string }
>()("@billet/backend-admin/PanelEnvironment") {}

/** The admin API paths, under `/admin/api`. */
export const adminApi = {
  me: "/admin/api/me",
  overview: "/admin/api/overview",
  appEvents: "/admin/api/app-events",
  flags: "/admin/api/flags",
  flag: "/admin/api/flags/:key",
  experiments: "/admin/api/experiments",
  experimentAction: "/admin/api/experiments/:key/:action",
  history: "/admin/api/history",
  pair: "/admin/api/pairs/:pairId",
  pairOverride: "/admin/api/pairs/:pairId/overrides/:key",
  status: "/admin/api/status",
  statusHistory: "/admin/api/status/history",
} as const;

/** The read-only API for agents' service tokens, under `/admin/api/agent`. GET only. */
export const agentApiPrefix = "/admin/api/agent/";
export const agentApi = {
  overview: "/admin/api/agent/overview",
  experiments: "/admin/api/agent/experiments",
  flags: "/admin/api/agent/flags",
  flagHistory: "/admin/api/agent/flag-history",
  pair: "/admin/api/agent/pairs/:pairId",
  status: "/admin/api/agent/status",
  statusHistory: "/admin/api/agent/status-history",
} as const;

// Absent values go out as `null`, so the page never has to tell `undefined` from a missing field.
const respondJson = (body: unknown, status = 200) =>
  HttpServerResponse.text(
    JSON.stringify(body, (_, value: unknown) => value ?? null),
    {
      status,
      contentType: "application/json",
      headers: { "cache-control": "no-store" },
    },
  );

const fail = (status: number, error: string, extra: Record<string, unknown> = {}) =>
  Effect.succeed(respondJson({ error, ...extra }, status));

/** Turns every failure into a fixed JSON answer. Nothing from a storage error reaches the page. */
const guarded = <R>(effect: Effect.Effect<HttpServerResponse.HttpServerResponse, unknown, R>) =>
  effect.pipe(
    Effect.catch((error: unknown) => {
      const tag =
        typeof error === "object" && error !== null && "_tag" in error
          ? String((error as { _tag: unknown })._tag)
          : "";
      switch (tag) {
        case "FlagConfigConflict":
        case "AppStatusConflict":
          return fail(409, "conflict", { current: (error as { current: number }).current });
        case "SchemaError":
        case "HttpServerError":
          return fail(400, "invalid", { message: "The request is not in the expected shape." });
        case "NotFound":
          return fail(404, "not-found");
        default:
          return Effect.logError("admin request failed", tag || "unknown").pipe(
            Effect.andThen(fail(503, "unavailable")),
          );
      }
    }),
  );

class NotFound extends Data.TaggedError("NotFound")<{}> {}

const SaveBody = Schema.Struct({ config: FlagConfig, expectedVersion: Schema.Int });
const StatusBody = Schema.Struct({ status: AppStatus, expectedVersion: Schema.Int });
const StatusHistoryQuery = Schema.Struct({
  limit: Schema.optional(
    Schema.NumberFromString.check(Schema.isBetween({ minimum: 1, maximum: 200 })),
  ),
});
const RangeQuery = Schema.Struct({
  days: Schema.optional(Schema.Literals(["7", "30", "90"])),
});
const ActionBody = Schema.Struct({ expectedVersion: Schema.Int });
const OverrideBody = Schema.Struct({ variant: VariantId });
const KeyParams = Schema.Struct({ key: ExperimentKey });
const ActionParams = Schema.Struct({
  key: ExperimentKey,
  action: Schema.Literals(["start", "stop", "kill", "unkill"]),
});
const PairParams = Schema.Struct({ pairId: PairId });
const PairKeyParams = Schema.Struct({ pairId: PairId, key: ExperimentKey });
const HistoryQuery = Schema.Struct({
  key: Schema.optional(ExperimentKey),
  limit: Schema.optional(
    Schema.NumberFromString.check(Schema.isBetween({ minimum: 1, maximum: 500 })),
  ),
});

const itemOf = (entry: Experiment, current: Experiment, stored: StoredFlagConfig | undefined) => ({
  key: entry.key,
  kind: entry.kind,
  variants: entry.variants.map(({ id }) => id),
  config: configOf(current),
  version: stored?.version ?? 0,
  updatedAt: stored?.updatedAt ?? null,
  updatedBy: stored?.updatedBy ?? null,
});

const transitions: Record<
  "start" | "stop" | "kill" | "unkill",
  (config: FlagConfig) => FlagConfig
> = {
  start: (config) => ({ ...config, status: "running" }),
  stop: (config) => ({ ...config, status: "stopped" }),
  kill: (config) => ({ ...config, killed: true }),
  unkill: (config) => ({ ...config, killed: false }),
};

/**
 * The answers both the panel and the agents read, built on the same services so an agent sees
 * exactly what the panel shows. Needs no identity: who may call them is decided by the routes.
 */
const readHandlers = Effect.gen(function* () {
  const flags = yield* FlagsService;
  const configs = yield* FlagConfigRepository;
  const assignments = yield* FlagsRepository;
  const registry = yield* Experiments;
  const data = yield* AdminData;
  const digest = yield* Digest.Digest;
  const appStatus = yield* AppStatusStore;

  const items = Effect.gen(function* () {
    const stored = new Map((yield* configs.all).map((row) => [row.key, row]));
    const current = yield* flags.current;
    return registry.map((entry, index) =>
      itemOf(entry, current[index] ?? entry, stored.get(entry.key)),
    );
  });

  const entryOf = (key: ExperimentKey) => {
    const entry = registry.find((candidate) => candidate.key === key);
    return entry === undefined ? Effect.fail(new NotFound()) : Effect.succeed(entry);
  };

  const overview = Effect.gen(function* () {
    const { days } = yield* HttpServerRequest.schemaSearchParams(RangeQuery);
    const [events, rows, users] = yield* Effect.all([
      data.events,
      data.assignments,
      data.userCount,
    ]);
    return respondJson(
      buildOverview(
        events,
        rows,
        users,
        utcDay(yield* Clock.currentTimeMillis),
        Number(days ?? 30),
      ),
    );
  }).pipe(guarded);

  const appEvents = Effect.gen(function* () {
    const { days } = yield* HttpServerRequest.schemaSearchParams(RangeQuery);
    return respondJson(
      buildAppEvents(
        yield* data.events,
        utcDay(yield* Clock.currentTimeMillis),
        Number(days ?? 30),
        yield* data.details,
      ),
    );
  }).pipe(guarded);

  const flagList = Effect.gen(function* () {
    return respondJson({ items: yield* items });
  }).pipe(guarded);

  const experiments = Effect.gen(function* () {
    const [list, events, rows] = yield* Effect.all([items, data.events, data.assignments]);
    const report = buildReport(events, rows, utcDay(yield* Clock.currentTimeMillis));
    const results = new Map(report.experiments.map((experiment) => [experiment.key, experiment]));
    return respondJson({
      items: list.map((item) => {
        const result = results.get(item.key);
        return {
          ...item,
          results:
            result === undefined
              ? null
              : {
                  variants: result.variants,
                  caution: result.caution,
                  verdict: verdictOf(result.variants),
                },
        };
      }),
    });
  }).pipe(guarded);

  const history = Effect.gen(function* () {
    const { key, limit } = yield* HttpServerRequest.schemaSearchParams(HistoryQuery);
    return respondJson({ changes: yield* configs.history(key, limit ?? 100) });
  }).pipe(guarded);

  const pair = Effect.gen(function* () {
    const { pairId } = yield* HttpRouter.schemaPathParams(PairParams);
    const [found, stored, overrides, events] = yield* Effect.all([
      data.pair(pairId),
      assignments.find(pairId),
      configs.overridesOf(pairId),
      data.events,
    ]);
    const own = events.filter((row) => row.pairId === pairId);
    if (found.members === 0 && stored.length === 0 && own.length === 0) {
      return yield* new NotFound();
    }
    const counts = new Map<string, number>();
    for (const row of own) counts.set(row.name, (counts.get(row.name) ?? 0) + row.count);
    // The panel does not know the pair's build, so version targeting is judged as unknown.
    const decisions = yield* flags.explain(pairId, "unknown");
    return respondJson({
      pairId,
      pairHash: yield* pairHashOf(pairId).pipe(Effect.provideService(Digest.Digest, digest)),
      members: found.members,
      pairedAt: found.pairedAt,
      assignments: stored.map(({ experimentKey, variant, assignedAt }) => ({
        key: experimentKey,
        variant,
        assignedAt,
      })),
      overrides: overrides.map(({ experimentKey, variant, setAt, setBy }) => ({
        key: experimentKey,
        variant,
        setAt,
        setBy,
      })),
      decisions,
      events: [...counts].map(([name, count]) => ({ name, count })),
    });
  }).pipe(guarded);

  const status = Effect.gen(function* () {
    return respondJson(yield* appStatus.current);
  }).pipe(guarded);

  const statusHistory = Effect.gen(function* () {
    const { limit } = yield* HttpServerRequest.schemaSearchParams(StatusHistoryQuery);
    return respondJson({ changes: yield* appStatus.history(limit ?? 50) });
  }).pipe(guarded);

  return {
    flags,
    configs,
    appStatus,
    items,
    entryOf,
    overview,
    appEvents,
    flagList,
    experiments,
    history,
    pair,
    status,
    statusHistory,
  };
});

/**
 * The admin JSON API. Needs `CurrentAdmin`, which only the Access check provides for a person:
 * these routes are never reachable without it (see `admin-fetch` in the platform package).
 */
export const AdminRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const { flags, configs, appStatus, entryOf, ...reads } = yield* readHandlers;
    const admin = yield* CurrentAdmin;
    const environment = yield* PanelEnvironment;

    const save = (
      key: ExperimentKey,
      config: FlagConfig,
      expectedVersion: number,
      action: FlagChangeAction,
    ) =>
      Effect.gen(function* () {
        const entry = yield* entryOf(key);
        const applied = applyConfig(entry, config);
        if ("error" in applied)
          return respondJson({ error: "invalid", message: applied.error }, 400);
        const { email } = admin;
        const saved = yield* configs.save({
          key,
          config,
          expectedVersion,
          action,
          by: email,
          at: yield* Clock.currentTimeMillis,
        });
        return respondJson(itemOf(entry, applied.experiment, saved));
      });

    yield* router.add(
      "GET",
      adminApi.me,
      Effect.sync(() => respondJson({ email: admin.email, environment: environment.name })),
    );
    yield* router.add("GET", adminApi.overview, reads.overview);
    yield* router.add("GET", adminApi.appEvents, reads.appEvents);
    yield* router.add("GET", adminApi.flags, reads.flagList);
    yield* router.add("GET", adminApi.experiments, reads.experiments);
    yield* router.add("GET", adminApi.history, reads.history);
    yield* router.add("GET", adminApi.pair, reads.pair);
    yield* router.add("GET", adminApi.status, reads.status);
    yield* router.add("GET", adminApi.statusHistory, reads.statusHistory);

    // Maintenance, the minimum build and the notice. Saved whole, with the version read, so two
    // tabs can't overwrite each other unseen; every save is kept in the history with the email.
    yield* router.add(
      "PUT",
      adminApi.status,
      Effect.gen(function* () {
        const body = yield* HttpServerRequest.schemaBodyJson(StatusBody);
        const saved = yield* appStatus.save({
          status: body.status,
          expectedVersion: body.expectedVersion,
          by: admin.email,
          at: yield* Clock.currentTimeMillis,
        });
        return respondJson(saved);
      }).pipe(guarded),
    );

    yield* router.add(
      "PUT",
      adminApi.flag,
      Effect.gen(function* () {
        const { key } = yield* HttpRouter.schemaPathParams(KeyParams);
        const body = yield* HttpServerRequest.schemaBodyJson(SaveBody);
        return yield* save(key, body.config, body.expectedVersion, "edit");
      }).pipe(guarded),
    );

    yield* router.add(
      "POST",
      adminApi.experimentAction,
      Effect.gen(function* () {
        const { key, action } = yield* HttpRouter.schemaPathParams(ActionParams);
        const { expectedVersion } = yield* HttpServerRequest.schemaBodyJson(ActionBody);
        const current = (yield* flags.current).find((experiment) => experiment.key === key);
        if (current === undefined) return yield* new NotFound();
        return yield* save(key, transitions[action](configOf(current)), expectedVersion, action);
      }).pipe(guarded),
    );

    yield* router.add(
      "PUT",
      adminApi.pairOverride,
      Effect.gen(function* () {
        const { pairId, key } = yield* HttpRouter.schemaPathParams(PairKeyParams);
        const { variant } = yield* HttpServerRequest.schemaBodyJson(OverrideBody);
        const entry = yield* entryOf(key);
        if (!entry.variants.some(({ id }) => id === variant)) {
          return respondJson(
            { error: "invalid", message: `${key} has no variant ${variant}` },
            400,
          );
        }
        const { email } = admin;
        yield* configs.setOverride({
          pairId,
          experimentKey: key,
          variant,
          setAt: yield* Clock.currentTimeMillis,
          setBy: email,
        });
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(guarded),
    );

    yield* router.add(
      "DELETE",
      adminApi.pairOverride,
      Effect.gen(function* () {
        const { pairId, key } = yield* HttpRouter.schemaPathParams(PairKeyParams);
        yield* entryOf(key);
        const { email } = admin;
        yield* configs.clearOverride({
          pairId,
          experimentKey: key,
          by: email,
          at: yield* Clock.currentTimeMillis,
        });
        return HttpServerResponse.empty({ status: 204 });
      }).pipe(guarded),
    );
  }),
).pipe(Layer.orDie);

/**
 * The read-only API for agents: the panel's reads, GET only, no identity and no route that
 * changes anything. `admin-fetch` serves it only to a service token, after the Access check.
 */
export const AgentRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const reads = yield* readHandlers;
    yield* router.add("GET", agentApi.overview, reads.overview);
    yield* router.add("GET", agentApi.experiments, reads.experiments);
    yield* router.add("GET", agentApi.flags, reads.flagList);
    yield* router.add("GET", agentApi.flagHistory, reads.history);
    yield* router.add("GET", agentApi.pair, reads.pair);
    yield* router.add("GET", agentApi.status, reads.status);
    yield* router.add("GET", agentApi.statusHistory, reads.statusHistory);
  }),
).pipe(Layer.orDie);
