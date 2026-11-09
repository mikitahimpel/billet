import { Effect, Option, Schema } from "effect";
import { describe, expect, it } from "vitest";
import { UserId } from "@billet/contracts-domain/ids";
import type { DemoPartnerRepository } from "../src/demo-partner-repository.ts";

const user = Schema.decodeSync(UserId);

export const contractOwners = ["owner-a", "owner-b"] as const;

const [ana, ben] = contractOwners.map((id) => user(id)) as [UserId, UserId];
const bot = (name: string) => user(`bot-${name}`);

/** `make` must return an empty repository in which `contractOwners` exist. */
export const describeDemoPartnerRepositoryContract = (
  name: string,
  make: () => Promise<DemoPartnerRepository["Service"]>,
): void => {
  describe(`DemoPartnerRepository contract: ${name}`, () => {
    it("finds each owner's own bot", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.create({ botId: bot("1"), ownerId: ana, createdAt: 1_000 });
          return [yield* repository.botOf(ana), yield* repository.botOf(ben)];
        }),
      );
      expect(found).toEqual([Option.some(bot("1")), Option.none()]);
    });

    it("tells a bot from its owner and from anyone else", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.create({ botId: bot("1"), ownerId: ana, createdAt: 1_000 });
          return [
            yield* repository.isBot(bot("1")),
            yield* repository.isBot(ana),
            yield* repository.isBot(ben),
          ];
        }),
      );
      expect(found).toEqual([true, false, false]);
    });

    it("refuses a second bot for one owner, keeping the first", async () => {
      const repository = await make();
      const [second, found] = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.create({ botId: bot("1"), ownerId: ana, createdAt: 1_000 });
          const refused = yield* repository
            .create({ botId: bot("2"), ownerId: ana, createdAt: 2_000 })
            .pipe(Effect.exit);
          return [refused._tag, yield* repository.botOf(ana)] as const;
        }),
      );
      expect(second).toBe("Failure");
      expect(found).toEqual(Option.some(bot("1")));
    });

    it("forgets a bot, so its owner can have another", async () => {
      const repository = await make();
      const found = await Effect.runPromise(
        Effect.gen(function* () {
          yield* repository.create({ botId: bot("1"), ownerId: ana, createdAt: 1_000 });
          yield* repository.create({ botId: bot("2"), ownerId: ben, createdAt: 1_000 });
          yield* repository.forget(bot("1"));
          yield* repository.forget(bot("unknown"));
          const forgotten = yield* repository.botOf(ana);
          yield* repository.create({ botId: bot("3"), ownerId: ana, createdAt: 2_000 });
          return [forgotten, yield* repository.botOf(ana), yield* repository.botOf(ben)];
        }),
      );
      expect(found).toEqual([Option.none(), Option.some(bot("3")), Option.some(bot("2"))]);
    });
  });
};
