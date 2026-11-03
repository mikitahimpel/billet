import { Context, Effect, Layer, type Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PartnerLeft } from "@billet/contracts-http-api/account";

/**
 * What the app should tell a user about their account: for now, that their partner left. A notice
 * is a courtesy, never a condition of a request, so it cannot fail; an implementation that can't
 * read it answers none.
 */
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
