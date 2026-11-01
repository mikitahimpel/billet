import { env } from "cloudflare:workers";
import { Effect, Exit, Layer, Option, Schema, Scope } from "effect";
import { beforeEach, describe, expect, it } from "vitest";
import { PairingRepository, type StoredInvite } from "@billet/backend-pairing/pairing-repository";
import {
  contractUsers,
  describePairingRepositoryContract,
} from "@billet/backend-pairing/test/pairing-repository-contract";
import { UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PairingRepositoryLive } from "../src/pairing-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(
        PairingRepositoryLive(binding),
        yield* Scope.make(),
      );
      return context.mapUnsafe.get(PairingRepository.key) as PairingRepository["Service"];
    }),
  );

const user = Schema.decodeSync(UserId);
const pair = Schema.decodeSync(PairId);

const addUsers = (ids: ReadonlyArray<string>) =>
  env.DB.batch(
    ids.map((id) =>
      env.DB.prepare("INSERT INTO users (id, apple_subject, created_at) VALUES (?, ?, 1)").bind(
        id,
        `subject-${id}`,
      ),
    ),
  );

const invite = (owner: string, codeHash = `hash-${owner}`): StoredInvite => ({
  codeHash,
  ownerId: user(owner),
  createdAt: 1_000,
  expiresAt: 2_000,
});

const claimBy = (repository: PairingRepository["Service"], claimer: string, codeHash: string) =>
  Effect.runPromise(
    repository
      .claimInvite({
        codeHash,
        claimerId: user(claimer),
        pairId: pair(`${claimer}-${codeHash}`),
        now: 1_500,
      })
      .pipe(
        Effect.as("claimed"),
        Effect.catch(({ _tag }) => Effect.succeed(_tag)),
      ),
  );

const members = async () =>
  (
    await env.DB.prepare("SELECT user_id, pair_id FROM pair_members ORDER BY user_id").all<{
      user_id: string;
      pair_id: string;
    }>()
  ).results;

const countOf = async (table: string) =>
  (await env.DB.prepare(`SELECT count(*) AS total FROM ${table}`).first<{ total: number }>())
    ?.total;

describePairingRepositoryContract("D1", async () => {
  await resetDirectory();
  await addUsers(contractUsers);
  return repositoryOn(env.DB);
});

describe("PairingRepositoryLive on D1", () => {
  beforeEach(resetDirectory);

  it("lets exactly one of two concurrent claims of one code succeed", async () => {
    await addUsers(["owner", "first", "second"]);
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.saveInvite(invite("owner")));

    const results = await Promise.all([
      claimBy(repository, "first", "hash-owner"),
      claimBy(repository, "second", "hash-owner"),
    ]);

    expect(results.toSorted()).toEqual(["InvalidInvite", "claimed"]);
    expect(await members()).toHaveLength(2);
    expect(await countOf("invites")).toBe(0);
  });

  it("lets exactly one of many concurrent claims of one code succeed", async () => {
    const claimers = Array.from({ length: 16 }, (_, index) => `claimer-${index}`);
    await addUsers(["owner", ...claimers]);
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.saveInvite(invite("owner")));

    const results = await Promise.all(
      claimers.map((claimer) => claimBy(repository, claimer, "hash-owner")),
    );

    expect(results.filter((result) => result === "claimed")).toHaveLength(1);
    expect(results.filter((result) => result === "InvalidInvite")).toHaveLength(15);
    const stored = await members();
    expect(stored).toHaveLength(2);
    expect(new Set(stored.map(({ pair_id }) => pair_id)).size).toBe(1);
  });

  it("gives one user one partner when it claims two codes at once", async () => {
    await addUsers(["owner-a", "owner-b", "claimer"]);
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.saveInvite(invite("owner-a")));
    await Effect.runPromise(repository.saveInvite(invite("owner-b")));

    const results = await Promise.all([
      claimBy(repository, "claimer", "hash-owner-a"),
      claimBy(repository, "claimer", "hash-owner-b"),
    ]);

    expect(results.toSorted()).toEqual(["AlreadyPaired", "claimed"]);
    expect(await members()).toHaveLength(2);
    expect(await countOf("invites")).toBe(1);
  });

  it("pairs once when two users claim each other's code at once", async () => {
    await addUsers(["ana", "ben"]);
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.saveInvite(invite("ana")));
    await Effect.runPromise(repository.saveInvite(invite("ben")));

    const results = await Promise.all([
      claimBy(repository, "ana", "hash-ben"),
      claimBy(repository, "ben", "hash-ana"),
    ]);

    expect(results.toSorted()).toEqual(["AlreadyPaired", "claimed"]);
    expect(await members()).toHaveLength(2);
    expect(await countOf("invites")).toBe(0);
  });

  it("writes nothing when any step of a claim fails", async () => {
    await addUsers(["owner", "claimer"]);
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.saveInvite(invite("owner")));

    const exit = await Effect.runPromiseExit(
      repository.claimInvite({
        codeHash: "hash-owner",
        claimerId: user("no-such-user"),
        pairId: pair("pair"),
        now: 1_500,
      }),
    );

    expect(Exit.isFailure(exit)).toBe(true);
    expect(await members()).toEqual([]);
    expect(await countOf("invites")).toBe(1);
  });

  it("empties the pair lookup on unpair, and keeps the users", async () => {
    await addUsers(["ana", "ben"]);
    const repository = await repositoryOn(env.DB);
    await Effect.runPromise(repository.saveInvite(invite("ana")));
    await claimBy(repository, "ben", "hash-ana");
    expect(await members()).toHaveLength(2);

    await Effect.runPromise(repository.unpair(user("ana")));

    expect(await countOf("pair_members")).toBe(0);
    expect(await countOf("users")).toBe(2);
    const found = await Effect.runPromise(repository.findPair(user("ben")));
    expect(Option.isNone(found)).toBe(true);
  });

  it("refuses a second pair row for a user in the table itself", async () => {
    await addUsers(["ana"]);
    const insert = (pairId: string) =>
      env.DB.prepare("INSERT INTO pair_members (user_id, pair_id, created_at) VALUES ('ana', ?, 1)")
        .bind(pairId)
        .run();
    await insert("pair-1");
    await expect(insert("pair-2")).rejects.toThrow();
  });

  it.each([
    [
      "a single statement",
      (repository: PairingRepository["Service"]) => repository.findPair(user("hash-secret")),
    ],
    [
      "a batch",
      (repository: PairingRepository["Service"]) => repository.saveInvite(invite("hash-secret")),
    ],
  ])("reports PairingUnavailable when %s fails", async (_, run) => {
    const broken = {
      prepare: () => {
        throw new Error("D1 is down, code hash hash-secret");
      },
    } as unknown as D1Database;
    const exit = await Effect.runPromiseExit(run(await repositoryOn(broken)));
    expect(Exit.isFailure(exit)).toBe(true);
    const text = JSON.stringify(exit);
    expect(text).toContain("directory-unavailable");
    expect(text).not.toContain("code hash");
  });
});
