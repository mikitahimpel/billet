import { env } from "cloudflare:workers";
import { Effect, Exit, Layer, Schema, Scope } from "effect";
import { beforeEach, describe, expect, it } from "vitest";
import { DemoPartnerRepository } from "@billet/backend-demo-partner/demo-partner-repository";
import {
  contractOwners,
  describeDemoPartnerRepositoryContract,
} from "@billet/backend-demo-partner/test/demo-partner-repository-contract";
import { UserId } from "@billet/contracts-domain/ids";
import { DemoPartnerRepositoryLive } from "../src/demo-partner-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(
        DemoPartnerRepositoryLive(binding),
        yield* Scope.make(),
      );
      return context.mapUnsafe.get(DemoPartnerRepository.key) as DemoPartnerRepository["Service"];
    }),
  );

const user = Schema.decodeSync(UserId);

const addUsers = (ids: ReadonlyArray<string>) =>
  env.DB.batch(
    ids.map((id) => env.DB.prepare("INSERT INTO users (id, created_at) VALUES (?, 1)").bind(id)),
  );

const userIds = async () =>
  (await env.DB.prepare("SELECT id FROM users ORDER BY id").all<{ id: string }>()).results.map(
    ({ id }) => id,
  );

describeDemoPartnerRepositoryContract("D1", async () => {
  await resetDirectory();
  await addUsers(contractOwners);
  return repositoryOn(env.DB);
});

describe("DemoPartnerRepositoryLive on D1", () => {
  beforeEach(resetDirectory);

  it("opens the bot as a user, and keeps it when it forgets the bot", async () => {
    await addUsers(["owner"]);
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(
      repository.create({ botId: user("bot"), ownerId: user("owner"), createdAt: 5 }),
    );
    expect(await userIds()).toEqual(["bot", "owner"]);
    await Effect.runPromise(repository.forget(user("bot")));
    expect(await userIds()).toEqual(["bot", "owner"]);
  });

  it("writes no bot when the record is refused", async () => {
    await addUsers(["owner"]);
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(
      repository.create({ botId: user("bot-1"), ownerId: user("owner"), createdAt: 5 }),
    );
    const exit = await Effect.runPromiseExit(
      repository.create({ botId: user("bot-2"), ownerId: user("owner"), createdAt: 6 }),
    );
    expect(Exit.isFailure(exit)).toBe(true);
    expect(JSON.stringify(exit)).toContain("directory-unavailable");
    expect(await userIds()).toEqual(["bot-1", "owner"]);
  });

  it.each([["bot"], ["owner"]])("drops the record with the %s's user", async (deleted) => {
    await addUsers(["owner"]);
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(
      repository.create({ botId: user("bot"), ownerId: user("owner"), createdAt: 5 }),
    );
    await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(deleted).run();
    expect(await env.DB.prepare("SELECT * FROM demo_partners").all()).toMatchObject({
      results: [],
    });
  });
});
