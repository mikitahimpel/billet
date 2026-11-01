import { Effect, Option } from "effect";
import type { TokenHash } from "@billet/backend-auth/auth-repository";
import type { UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { AlreadyPaired, InvalidInvite } from "../src/pairing-error.ts";
import type { PairingRepository, StoredInvite } from "../src/pairing-repository.ts";

export interface InMemoryPairingRepository {
  readonly repository: PairingRepository["Service"];
  /** Everything stored, as text, for assertions about what is and isn't kept. */
  readonly dump: Effect.Effect<string>;
}

/** The test double for `PairingRepository`. Single-threaded, so each method is trivially atomic. */
export const makeInMemoryPairingRepository = (): InMemoryPairingRepository => {
  const invites = new Map<TokenHash, StoredInvite>();
  const pairs = new Map<UserId, PairId>();

  const removeInvites = (shouldRemove: (invite: StoredInvite) => boolean) => {
    for (const [hash, invite] of invites) {
      if (shouldRemove(invite)) invites.delete(hash);
    }
  };

  const repository: PairingRepository["Service"] = {
    saveInvite: (invite) =>
      Effect.suspend(() => {
        if (pairs.has(invite.ownerId)) return Effect.fail(new AlreadyPaired());
        removeInvites(
          ({ ownerId, expiresAt }) => ownerId === invite.ownerId || expiresAt <= invite.createdAt,
        );
        invites.set(invite.codeHash, invite);
        return Effect.void;
      }),
    claimInvite: ({ codeHash, claimerId, pairId, now }) =>
      Effect.suspend((): Effect.Effect<void, AlreadyPaired | InvalidInvite> => {
        if (pairs.has(claimerId)) return Effect.fail(new AlreadyPaired());
        const invite = invites.get(codeHash);
        if (invite === undefined || invite.expiresAt <= now || invite.ownerId === claimerId) {
          return Effect.fail(new InvalidInvite());
        }
        pairs.set(claimerId, pairId);
        pairs.set(invite.ownerId, pairId);
        removeInvites(({ ownerId }) => ownerId === claimerId || ownerId === invite.ownerId);
        return Effect.void;
      }),
    findPair: (userId) => Effect.sync(() => Option.fromNullishOr(pairs.get(userId))),
    unpair: (userId) =>
      Effect.sync(() => {
        const pairId = pairs.get(userId);
        for (const [member, memberPair] of pairs) {
          if (memberPair === pairId) pairs.delete(member);
        }
      }),
  };

  const dump = Effect.sync(() => JSON.stringify({ invites: [...invites], pairs: [...pairs] }));

  return { repository, dump };
};
