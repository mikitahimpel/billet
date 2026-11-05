import { Effect, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import { DemoPartnerUnavailable } from "../src/demo-partner-error.ts";
import type { DemoPartnerRepository, StoredDemoPartner } from "../src/demo-partner-repository.ts";

export interface InMemoryDemoPartnerRepository {
  readonly repository: DemoPartnerRepository["Service"];
  /** The bots opened as users, forgotten or not. */
  readonly bots: ReadonlySet<UserId>;
}

/** The test double for `DemoPartnerRepository`. Single-threaded, so each method is atomic. */
export const makeInMemoryDemoPartnerRepository = (): InMemoryDemoPartnerRepository => {
  const demos = new Map<UserId, StoredDemoPartner>();
  const bots = new Set<UserId>();

  const repository: DemoPartnerRepository["Service"] = {
    create: (demo) =>
      Effect.suspend(() => {
        if (demos.has(demo.ownerId) || bots.has(demo.botId)) {
          return Effect.fail(new DemoPartnerUnavailable({ reason: "directory-unavailable" }));
        }
        demos.set(demo.ownerId, demo);
        bots.add(demo.botId);
        return Effect.void;
      }),
    botOf: (ownerId) =>
      Effect.sync(() => Option.map(Option.fromNullishOr(demos.get(ownerId)), ({ botId }) => botId)),
    forget: (botId) =>
      Effect.sync(() => {
        for (const [ownerId, demo] of demos) {
          if (demo.botId === botId) demos.delete(ownerId);
        }
      }),
  };

  return { repository, bots };
};
