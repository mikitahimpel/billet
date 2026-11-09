import { Clock, Context, Effect, Layer, Option, type Redacted } from "effect";
import type { MediaKey, UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { MediaStore } from "@billet/backend-notes/media-store";
import { PairRooms } from "@billet/backend-notes/pair-rooms";
import { PairingRepository } from "@billet/backend-pairing/pairing-repository";
import { AccountUnavailable } from "./account-error.ts";
import { AccountRepository } from "./account-repository.ts";
import { AppleTokenRevoker } from "./apple-token-revoker.ts";

const unavailable = (reason: string) => () => new AccountUnavailable({ reason });

/**
 * App Store guideline 5.1.1(v). The pair's cat goes too; the partner keeps their notes.
 */
export class AccountDeletion extends Context.Service<
  AccountDeletion,
  {
    /**
     * A failure before the final atomic write leaves the account, so the app can retry.
     */
    readonly deleteAccount: (
      userId: UserId,
      appleAuthorizationCode: Option.Option<Redacted.Redacted<string>>,
    ) => Effect.Effect<void, AccountUnavailable>;
  }
>()("@billet/backend-account/AccountDeletion") {
  static readonly layer: Layer.Layer<
    AccountDeletion,
    never,
    AccountRepository | AppleTokenRevoker | PairingRepository | PairRooms | MediaStore
  > = Layer.effect(
    AccountDeletion,
    Effect.gen(function* () {
      const repository = yield* AccountRepository;
      const revoker = yield* AppleTokenRevoker;
      const pairing = yield* PairingRepository;
      const rooms = yield* PairRooms;
      const media = yield* MediaStore;

      /** Deletes the user's notes in one room and every image of theirs under its prefix. */
      const clearRoom = Effect.fn("AccountDeletion.clearRoom")(function* (
        pairId: PairId,
        userId: UserId,
      ) {
        const notes = yield* rooms.forgetMember(pairId, userId);
        const uploaded = yield* media.uploadedBy(pairId, userId);
        const images = notes.flatMap(({ note }) => (note._tag === "Text" ? [] : [note.image]));
        const keys = new Set<MediaKey>([...uploaded, ...images]);
        yield* media.remove([...keys]);
      });

      const deleteAccount = Effect.fn("AccountDeletion.deleteAccount")(function* (
        userId: UserId,
        appleAuthorizationCode: Option.Option<Redacted.Redacted<string>>,
      ): Effect.fn.Return<void, AccountUnavailable> {
        // First, while the account still exists: a code is only good for a few minutes.
        if (Option.isSome(appleAuthorizationCode)) {
          const outcome = yield* revoker.revoke(appleAuthorizationCode.value);
          yield* Effect.logInfo("apple token revocation", outcome);
        }

        const current = yield* pairing
          .findPair(userId)
          .pipe(Effect.mapError(unavailable("directory-unavailable")));
        const partner = Option.isNone(current)
          ? Option.none<UserId>()
          : Option.fromNullishOr(
              (yield* pairing
                .findMembers(current.value)
                .pipe(Effect.mapError(unavailable("directory-unavailable")))).find(
                (member) => member !== userId,
              ),
            );

        const pairs = yield* repository.pairsOf(userId);
        for (const pairId of pairs) {
          yield* clearRoom(pairId, userId).pipe(Effect.mapError(unavailable("notes-unavailable")));
        }

        yield* repository.erase({ userId, partner, at: yield* Clock.currentTimeMillis });

        // A note or socket reconnect between clearing the room and the erase would outlive the
        // account; one more pass catches both. Its failure is logged and the deletion stands.
        if (Option.isSome(current)) {
          yield* clearRoom(current.value, userId).pipe(
            Effect.catchCause(() => Effect.logWarning("account deletion follow-up failed")),
          );
        }
      });

      return AccountDeletion.of({ deleteAccount });
    }),
  );
}
