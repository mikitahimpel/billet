import { env } from "cloudflare:workers";
import { Effect, Layer, Scope } from "effect";
import { beforeAll } from "vitest";
import { PaymentsRepository } from "@billet/backend-payments/payments-repository";
import { paymentsRepositoryContract } from "@billet/backend-payments/test/payments-repository-contract";
import { PaymentsRepositoryLive } from "../src/payments-repository-live.ts";
import { resetDirectory } from "./directory-migrations.ts";

const repositoryOn = (binding: D1Database) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const context = yield* Layer.buildWithScope(
        PaymentsRepositoryLive(binding),
        yield* Scope.make(),
      );
      return context.mapUnsafe.get(PaymentsRepository.key) as PaymentsRepository["Service"];
    }),
  );

beforeAll(async () => {
  await resetDirectory();
});

// Owners are fresh per test, so the tests share one database.
paymentsRepositoryContract("D1", async () => ({
  repository: await repositoryOn(env.DB),
  spend: async (owner, stamps) => {
    await env.DB.prepare(
      `INSERT INTO stamp_ledger (id, owner_id, kind, amount, product_id, original_transaction_id, at)
       VALUES (?, ?, 'refund', ?, 'spent', 'spent', 0)`,
    )
      .bind(`spend:${crypto.randomUUID()}`, owner, -stamps)
      .run();
  },
}));
