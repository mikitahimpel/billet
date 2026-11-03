import { env } from "cloudflare:workers";
import { Effect, Layer, Schema, Scope } from "effect";
import { beforeEach, describe, expect, it } from "vitest";
import { ExperimentKey, VariantId } from "@billet/contracts-domain/flags";
import { FlagConfigRepository } from "@billet/backend-flags/flag-config-repository";
import { describeFlagConfigRepositoryContract } from "@billet/backend-flags/test/flag-config-repository-contract";
import {
  flagConfigCacheSeconds,
  flagConfigCacheUrl,
  FlagConfigRepositoryLive,
} from "../src/flag-config-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database, cache: Cache | undefined) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(
        FlagConfigRepositoryLive(binding, cache),
        yield* Scope.make(),
      );
      return context.mapUnsafe.get(FlagConfigRepository.key) as FlagConfigRepository["Service"];
    }),
  );

beforeEach(resetDirectory);

describeFlagConfigRepositoryContract("D1", () => repositoryOn(env.DB, undefined));
describeFlagConfigRepositoryContract("D1 behind the edge cache", () =>
  repositoryOn(env.DB, caches.default),
);

describe("the edge cache", () => {
  const key = Schema.decodeSync(ExperimentKey)("one");
  const variant = Schema.decodeSync(VariantId);
  const config = (exposure: number) => ({
    description: "",
    weights: { [variant("a")]: 1, [variant("b")]: 1 },
    default: variant("a"),
    exposure,
    status: "running" as const,
    killed: false,
    targeting: {},
  });

  it("serves the configurations from the cache for a short time, with a max-age", async () => {
    const repository = await repositoryOn(env.DB, caches.default);
    await Effect.runPromise(
      repository.save({
        key,
        config: config(10),
        expectedVersion: 0,
        action: "edit",
        by: "o",
        at: 1,
      }),
    );
    expect((await Effect.runPromise(repository.all))[0]?.config.exposure).toBe(10);
    const cached = await caches.default.match(flagConfigCacheUrl);
    expect(cached?.headers.get("cache-control")).toBe(`max-age=${flagConfigCacheSeconds}`);

    // A write that skips the repository is not seen until the cache entry goes.
    await env.DB.prepare("UPDATE flag_configs SET config = ?")
      .bind(JSON.stringify(config(90)))
      .run();
    expect((await Effect.runPromise(repository.all))[0]?.config.exposure).toBe(10);
    await caches.default.delete(flagConfigCacheUrl);
    expect((await Effect.runPromise(repository.all))[0]?.config.exposure).toBe(90);
  });

  it("drops the cached copy when the admin saves, so this colo sees the change at once", async () => {
    const repository = await repositoryOn(env.DB, caches.default);
    await Effect.runPromise(
      repository.save({
        key,
        config: config(10),
        expectedVersion: 0,
        action: "edit",
        by: "o",
        at: 1,
      }),
    );
    await Effect.runPromise(repository.all);
    await Effect.runPromise(
      repository.save({
        key,
        config: config(20),
        expectedVersion: 1,
        action: "kill",
        by: "o",
        at: 2,
      }),
    );
    expect((await Effect.runPromise(repository.all))[0]?.config.exposure).toBe(20);
  });

  it("falls back to D1 when the cached copy is unreadable", async () => {
    const repository = await repositoryOn(env.DB, caches.default);
    await caches.default.put(
      flagConfigCacheUrl,
      new Response("not json", { headers: { "cache-control": "max-age=30" } }),
    );
    expect(await Effect.runPromise(repository.all)).toEqual([]);
  });
});
