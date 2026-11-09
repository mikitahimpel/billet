import { Context, Effect, Layer, type Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PartnerLeft } from "@billet/contracts-http-api/account";

/** A courtesy, never a condition of a request: it cannot fail, and an unreadable one is none. */
export class AccountNotices extends Context.Service<
  AccountNotices,
  {
    /** The partner who ended the user's last pair by leaving, while the user is still unpaired. */
    readonly partnerLeft: (userId: UserId) => Effect.Effect<Option.Option<PartnerLeft>>;
  }
>()("@billet/backend-auth/AccountNotices") {
  /** Never has a notice. For tests and for code that only signs people in. */
  static readonly none = Layer.succeed(AccountNotices, {
    partnerLeft: () => Effect.succeedNone,
  });
}
