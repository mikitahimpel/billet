import { Context, type Effect } from "effect";
import type { NoteText } from "@billet/contracts-domain/note";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { DemoPartnerUnavailable } from "./demo-partner-error.ts";

/** Wakes and stills the bot in a demo pair's room. Both are safe to repeat. */
export class DemoBots extends Context.Service<
  DemoBots,
  {
    /** From now on `bot` acts in the pair's room as `owner`'s partner. */
    readonly start: (
      pairId: PairId,
      owner: UserId,
      bot: UserId,
      /** Notes the bot sends as soon as it starts, so the room is not empty. */
      welcome?: ReadonlyArray<NoteText>,
    ) => Effect.Effect<void, DemoPartnerUnavailable>;
    readonly stop: (pairId: PairId) => Effect.Effect<void, DemoPartnerUnavailable>;
  }
>()("@billet/backend-demo-partner/DemoBots") {}
