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
import type { AdminIdentity } from "./access.ts";
import { AdminData } from "./admin-data.ts";
import { buildOverview } from "./admin-overview.ts";

/** Who is using the panel, as Cloudflare Access verified them. Every change is logged under it. */
export class CurrentAdmin extends Context.Service<CurrentAdmin, AdminIdentity>()(
  "@billet/backend-admin/CurrentAdmin",
) {}

/** The admin API paths, under `/admin/api`. */
export const adminApi = {
  me: "/admin/api/me",
  overview: "/admin/api/overview",
  flags: "/admin/api/flags",
  flag: "/admin/api/flags/:key",
  experiments: "/admin/api/experiments",
  experimentAction: "/admin/api/experiments/:key/:action",
  history: "/admin/api/history",
  pair: "/admin/api/pairs/:pairId",
  pairOverride: "/admin/api/pairs/:pairId/overrides/:key",
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
 * The admin JSON API. Needs `CurrentAdmin`, which only the Access check provides: these routes are
 * never reachable without it (see `admin-fetch` in the platform package).
 */
export const AdminRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const flags = yield* FlagsService;
    const configs = yield* FlagConfigRepository;
    const assignments = yield* FlagsRepository;
    const registry = yield* Experiments;
    const data = yield* AdminData;
    const digest = yield* Digest.Digest;
    const admin = yield* CurrentAdmin;

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
      Effect.sync(() => respondJson({ email: admin.email })),
    );

    yield* router.add(
      "GET",
      adminApi.overview,
      Effect.gen(function* () {
        const [events, rows, users] = yield* Effect.all([
          data.events,
          data.assignments,
          data.userCount,
        ]);
        return respondJson(
          buildOverview(events, rows, users, utcDay(yield* Clock.currentTimeMillis)),
        );
      }).pipe(guarded),
    );

    yield* router.add(
      "GET",
      adminApi.flags,
      Effect.gen(function* () {
        return respondJson({ items: yield* items });
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
      "GET",
      adminApi.experiments,
      Effect.gen(function* () {
        const [list, events, rows] = yield* Effect.all([items, data.events, data.assignments]);
        const report = buildReport(events, rows, utcDay(yield* Clock.currentTimeMillis));
        const results = new Map(
          report.experiments.map((experiment) => [experiment.key, experiment]),
        );
        return respondJson({
          items: list.map((item) => {
            const result = results.get(item.key);
            return {
              ...item,
              results:
                result === undefined
                  ? null
                  : { variants: result.variants, caution: result.caution },
            };
          }),
        });
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
      "GET",
      adminApi.history,
      Effect.gen(function* () {
        const { key, limit } = yield* HttpServerRequest.schemaSearchParams(HistoryQuery);
        return respondJson({ changes: yield* configs.history(key, limit ?? 100) });
      }).pipe(guarded),
    );

    yield* router.add(
      "GET",
      adminApi.pair,
      Effect.gen(function* () {
        const { pairId } = yield* HttpRouter.schemaPathParams(PairParams);
        const [pair, stored, overrides, events] = yield* Effect.all([
          data.pair(pairId),
          assignments.find(pairId),
          configs.overridesOf(pairId),
          data.events,
        ]);
        const own = events.filter((row) => row.pairId === pairId);
        if (pair.members === 0 && stored.length === 0 && own.length === 0) {
          return yield* new NotFound();
        }
        const counts = new Map<string, number>();
        for (const row of own) counts.set(row.name, (counts.get(row.name) ?? 0) + row.count);
        // The panel does not know the pair's build, so version targeting is judged as unknown.
        const decisions = yield* flags.explain(pairId, "unknown");
        return respondJson({
          pairId,
          pairHash: yield* pairHashOf(pairId).pipe(Effect.provideService(Digest.Digest, digest)),
          members: pair.members,
          pairedAt: pair.pairedAt,
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
