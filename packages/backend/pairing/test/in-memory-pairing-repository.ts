import { Effect, Option } from "effect";
import type { TokenHash } from "@billet/backend-auth/auth-repository";
import type { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import type { PairId } from "@billet/contracts-domain/pair-id";
import { AlreadyPaired, InvalidInvite } from "../src/pairing-error.ts";
import type { PairingRepository, PartnerReport, StoredInvite } from "../src/pairing-repository.ts";

export interface InMemoryPairingRepository {
  readonly repository: PairingRepository["Service"];
  /** Everything stored, as text, for assertions about what is and isn't kept. */
  readonly dump: Effect.Effect<string>;
}

/** The test double for `PairingRepository`. Single-threaded, so each method is trivially atomic. */
export const makeInMemoryPairingRepository = (): InMemoryPairingRepository => {
  const invites = new Map<TokenHash, StoredInvite>();
  const pairs = new Map<UserId, PairId>();
  const formed = new Map<PairId, EpochMillis>();
  const blocks = new Set<string>();
  const reports: PartnerReport[] = [];

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
        if (
          blocks.has(`${claimerId}>${invite.ownerId}`) ||
          blocks.has(`${invite.ownerId}>${claimerId}`)
        ) {
          return Effect.fail(new InvalidInvite());
        }
        pairs.set(claimerId, pairId);
        pairs.set(invite.ownerId, pairId);
        formed.set(pairId, now);
        removeInvites(({ ownerId }) => ownerId === claimerId || ownerId === invite.ownerId);
        return Effect.void;
      }),
    findPair: (userId) => Effect.sync(() => Option.fromNullishOr(pairs.get(userId))),
    pairedAt: (pairId) =>
      Effect.sync(() =>
        [...pairs.values()].includes(pairId)
          ? Option.fromNullishOr(formed.get(pairId))
          : Option.none(),
      ),
    findMembers: (pairId) =>
      Effect.sync(() =>
        [...pairs].filter(([, memberPair]) => memberPair === pairId).map(([member]) => member),
      ),
    unpair: (userId) =>
      Effect.sync(() => {
        const pairId = pairs.get(userId);
        for (const [member, memberPair] of pairs) {
          if (memberPair === pairId) pairs.delete(member);
        }
      }),
    block: ({ blocker, blocked }) =>
      Effect.sync(() => {
        blocks.add(`${blocker}>${blocked}`);
        const pairId = pairs.get(blocker);
        for (const [member, memberPair] of pairs) {
          if (memberPair === pairId) pairs.delete(member);
        }
      }),
    saveReport: (report) => Effect.sync(() => void reports.push(report)),
  };

  const dump = Effect.sync(() =>
    JSON.stringify({ invites: [...invites], pairs: [...pairs], blocks: [...blocks], reports }),
  );

  return { repository, dump };
};
