import { Context, Effect, Layer, Option } from "effect";
import type { LocalDay } from "@billet/contracts-domain/coins";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import type { DisplayName, MemberName } from "@billet/contracts-http-api/pair";
import type { PairingUnavailable } from "./pairing-error.ts";

/** Each user's display name and each pair's day together. Each method is atomic. */
export class PairProfileRepository extends Context.Service<
  PairProfileRepository,
  {
    readonly setName: (
      userId: UserId,
      name: DisplayName | null,
    ) => Effect.Effect<void, PairingUnavailable>;
    /** Only the users who have one. */
    readonly names: (
      users: ReadonlyArray<UserId>,
    ) => Effect.Effect<ReadonlyArray<MemberName>, PairingUnavailable>;
    /** False when `ifUnset` found a day already set, or the pair has ended. */
    readonly setTogetherSince: (
      pairId: PairId,
      day: LocalDay,
      ifUnset: boolean,
    ) => Effect.Effect<boolean, PairingUnavailable>;
    /** None until a partner sets it, and once the pair has ended. */
    readonly togetherSince: (
      pairId: PairId,
    ) => Effect.Effect<Option.Option<LocalDay>, PairingUnavailable>;
  }
>()("@billet/backend-pairing/PairProfileRepository") {
  /** Keeps nothing. For tests that never read a name or a day. */
  static readonly none = Layer.succeed(PairProfileRepository, {
    setName: () => Effect.void,
    names: () => Effect.succeed([]),
    setTogetherSince: () => Effect.succeed(false),
    togetherSince: () => Effect.succeed(Option.none()),
  });
}
