import { Effect, Option } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import { ReviewUnavailable } from "../src/review-error.ts";
import type {
  ReviewRepository,
  StoredReviewChange,
  StoredReviewCode,
} from "../src/review-repository.ts";

export interface InMemoryReviewRepository {
  readonly repository: ReviewRepository["Service"];
  /** The users opened as partners. */
  readonly users: ReadonlySet<UserId>;
  readonly codes: ReadonlyArray<StoredReviewCode>;
}

/** The test double for `ReviewRepository`. Single-threaded, so each method is atomic. */
export const makeInMemoryReviewRepository = (): InMemoryReviewRepository => {
  let partner: UserId | undefined;
  const users = new Set<UserId>();
  const codes: StoredReviewCode[] = [];
  const changes: StoredReviewChange[] = [];

  const revokeAll = (at: number) => {
    for (const [index, code] of codes.entries()) {
      if (code.revokedAt === null) codes[index] = { ...code, revokedAt: at };
    }
  };
  const change = (entry: Omit<StoredReviewChange, "id">) =>
    changes.push({ id: changes.length + 1, ...entry });

  const repository: ReviewRepository["Service"] = {
    partner: Effect.sync(() => Option.fromNullishOr(partner)),
    createPartner: ({ userId }) =>
      Effect.suspend(() => {
        if (partner !== undefined || users.has(userId)) {
          return Effect.fail(new ReviewUnavailable({ reason: "directory-unavailable" }));
        }
        partner = userId;
        users.add(userId);
        return Effect.void;
      }),
    isPartner: (userId) => Effect.sync(() => partner === userId),
    issue: (code) =>
      Effect.sync(() => {
        revokeAll(code.createdAt);
        codes.push({ ...code, revokedAt: null, claims: 0, lastClaimedAt: null });
        change({
          at: code.createdAt,
          by: code.createdBy,
          action: "issue",
          lastFour: code.lastFour,
        });
      }),
    revoke: ({ at, by }) =>
      Effect.sync(() => {
        revokeAll(at);
        change({ at, by, action: "revoke", lastFour: null });
      }),
    record: ({ at, by, action }) =>
      Effect.sync(() => void change({ at, by, action, lastFour: null })),
    liveCode: (codeHash, now) =>
      Effect.sync(() => {
        const code = codes.find((candidate) => candidate.codeHash === codeHash);
        return code === undefined || code.revokedAt !== null || code.expiresAt <= now
          ? Option.none()
          : Option.some(code.partnerId);
      }),
    claimed: (codeHash, at) =>
      Effect.sync(() => {
        const index = codes.findIndex((code) => code.codeHash === codeHash);
        const code = codes[index];
        if (code !== undefined)
          codes[index] = { ...code, claims: code.claims + 1, lastClaimedAt: at };
      }),
    codes: (limit) => Effect.sync(() => codes.toReversed().slice(0, limit)),
    changes: (limit) => Effect.sync(() => changes.toReversed().slice(0, limit)),
  };

  return { repository, users, codes };
};
