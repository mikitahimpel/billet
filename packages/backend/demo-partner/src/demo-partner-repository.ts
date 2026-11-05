import { Context, type Effect, type Option, Schema } from "effect";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type { DemoPartnerUnavailable } from "./demo-partner-error.ts";

/** What a `demo_partners` row holds. A test in `platform` fails if the table's columns differ. */
export const StoredDemoPartner = Schema.Struct({
  botId: UserId,
  ownerId: UserId,
  createdAt: EpochMillis,
});
export type StoredDemoPartner = typeof StoredDemoPartner.Type;

/**
 * Which user is whose demo partner. Every storage failure is `DemoPartnerUnavailable`.
 * `test/demo-partner-repository-contract.ts` is the behaviour any implementation must pass.
 */
export class DemoPartnerRepository extends Context.Service<
  DemoPartnerRepository,
  {
    /**
     * Opens the bot as a user and records it as the owner's demo partner, both or neither. An owner
     * has at most one: a second fails, keeping the first.
     */
    readonly create: (demo: StoredDemoPartner) => Effect.Effect<void, DemoPartnerUnavailable>;
    readonly botOf: (
      ownerId: UserId,
    ) => Effect.Effect<Option.Option<UserId>, DemoPartnerUnavailable>;
    /** Drops the record and keeps the bot's user. Does nothing for an unknown bot. */
    readonly forget: (botId: UserId) => Effect.Effect<void, DemoPartnerUnavailable>;
  }
>()("@billet/backend-demo-partner/DemoPartnerRepository") {}
