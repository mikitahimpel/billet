import { env } from "cloudflare:workers";
import { Effect, Layer, Option, Schema, Scope } from "effect";
import { beforeEach, expect, it } from "vitest";
import { PairProfileRepository } from "@billet/backend-pairing/pair-profile-repository";
import { LocalDay } from "@billet/contracts-domain/coins";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { DisplayName } from "@billet/contracts-http-api/pair";
import { PairProfileRepositoryLive } from "../src/pair-profile-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repository = () =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(
        PairProfileRepositoryLive(env.DB),
        yield* Scope.make(),
      );
      return context.mapUnsafe.get(PairProfileRepository.key) as PairProfileRepository["Service"];
    }),
  );

const user = Schema.decodeSync(UserId);
const name = Schema.decodeSync(DisplayName);
const day = Schema.decodeSync(LocalDay);
const pairId = Schema.decodeSync(PairId)("pair-1");
const [ana, ben] = [user("ana"), user("ben")];

beforeEach(async () => {
  await resetDirectory();
  await env.DB.batch([
    env.DB.prepare("INSERT INTO users (id, created_at) VALUES ('ana', 1), ('ben', 1)"),
    env.DB.prepare(
      "INSERT INTO pair_members (user_id, pair_id, created_at) VALUES ('ana', 'pair-1', 1), ('ben', 'pair-1', 1)",
    ),
  ]);
});

it("keeps names in the order asked and forgets a cleared one", async () => {
  const profiles = await repository();
  await Effect.runPromise(profiles.setName(ana, name("Ana")));
  await Effect.runPromise(profiles.setName(ben, name("Ben")));
  expect(await Effect.runPromise(profiles.names([ben, ana]))).toEqual([
    { userId: ben, displayName: "Ben" },
    { userId: ana, displayName: "Ana" },
  ]);
  await Effect.runPromise(profiles.setName(ana, null));
  expect(await Effect.runPromise(profiles.names([ana, ben]))).toEqual([
    { userId: ben, displayName: "Ben" },
  ]);
});

it("keeps one day per pair, which `ifUnset` never replaces, and drops it with the pair", async () => {
  const profiles = await repository();
  const run = <A>(effect: Effect.Effect<A, unknown>) => Effect.runPromise(effect);
  expect(await run(profiles.togetherSince(pairId))).toEqual(Option.none());
  expect(await run(profiles.setTogetherSince(pairId, day("2025-02-14"), true))).toBe(true);
  expect(await run(profiles.setTogetherSince(pairId, day("2024-01-01"), true))).toBe(false);
  expect(await run(profiles.togetherSince(pairId))).toEqual(Option.some("2025-02-14"));
  expect(await run(profiles.setTogetherSince(pairId, day("2024-01-01"), false))).toBe(true);
  expect(await run(profiles.togetherSince(pairId))).toEqual(Option.some("2024-01-01"));
  await env.DB.prepare("DELETE FROM pair_members").run();
  expect(await run(profiles.togetherSince(pairId))).toEqual(Option.none());
  expect(await run(profiles.setTogetherSince(pairId, day("2024-01-01"), false))).toBe(false);
});
