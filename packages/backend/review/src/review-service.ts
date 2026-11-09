import { Clock, Context, Duration, Effect, Layer, Option, Schema } from "effect";
import { Digest, SecureRandom } from "effect/crypto";
import { DemoBots } from "@billet/backend-demo-partner/demo-bots";
import { annotateRefs } from "@billet/backend-observability/opaque-ref";
import { AlreadyPaired, InvalidInvite } from "@billet/backend-pairing/pairing-error";
import { PairingService } from "@billet/backend-pairing/pairing-service";
import {
  type EpochMillis,
  inviteCodeAlphabet,
  ReviewCode,
  reviewCodeLength,
  UserId,
} from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import type { PairResponse } from "@billet/contracts-http-api/pair";
import { ReviewUnavailable } from "./review-error.ts";
import {
  type ReviewAction,
  ReviewRepository,
  type StoredReviewChange,
} from "./review-repository.ts";

/** How long a new code lives, at most. App Review rarely takes more than a week. */
export const reviewCodeMaxDays = 30;

const decodeReviewCode = Schema.decodeSync(ReviewCode);
const decodeUserId = Schema.decodeSync(UserId);
const encoder = new TextEncoder();

const unavailable =
  (reason: string) =>
  (cause: unknown): ReviewUnavailable =>
    new ReviewUnavailable({ reason, cause });

/** A code as the admin lists it: never the code, only its last four symbols. */
export interface ReviewCodeView {
  readonly lastFour: string;
  readonly createdAt: EpochMillis;
  readonly createdBy: string;
  readonly expiresAt: EpochMillis;
  readonly revokedAt: EpochMillis | null;
  readonly claims: number;
  readonly lastClaimedAt: EpochMillis | null;
  readonly live: boolean;
}

export interface ReviewStatus {
  readonly partner: UserId | null;
  /** The pair the partner is in now, if a reviewer claimed a code since the last wipe. */
  readonly pairId: PairId | null;
  readonly codes: ReadonlyArray<ReviewCodeView>;
  readonly changes: ReadonlyArray<StoredReviewChange>;
}

/** A new code, shown once to the admin who made it. */
export interface IssuedReviewCode {
  readonly code: ReviewCode;
  readonly lastFour: string;
  readonly expiresAt: EpochMillis;
}

/**
 * The App Review pair (docs/app-review.md). A review code pairs whoever claims it with the one
 * review partner, through an ordinary invite, so every rule of pairing holds. The partner's pair is
 * reset on each claim, and its room's bot acts for it only in that pair. Codes are made, revoked
 * and the pair wiped from the admin only, each change recorded under the admin's email.
 */
export class ReviewService extends Context.Service<
  ReviewService,
  {
    readonly claim: (
      claimerId: UserId,
      code: ReviewCode,
    ) => Effect.Effect<PairId, InvalidInvite | AlreadyPaired | ReviewUnavailable>;
    readonly status: Effect.Effect<ReviewStatus, ReviewUnavailable>;
    /** Makes a new code that lives `days`, revoking every earlier one. Opens the partner if needed. */
    readonly issue: (
      by: string,
      days: number,
    ) => Effect.Effect<IssuedReviewCode, ReviewUnavailable>;
    readonly revoke: (by: string) => Effect.Effect<void, ReviewUnavailable>;
    /** Ends the partner's pair, which deletes its room, notes and photos. */
    readonly wipe: (by: string) => Effect.Effect<void, ReviewUnavailable>;
  }
>()("@billet/backend-review/ReviewService") {
  static readonly layer: Layer.Layer<
    ReviewService,
    never,
    ReviewRepository | PairingService | DemoBots | Digest.Digest | SecureRandom.SecureRandom
  > = Layer.effect(
    ReviewService,
    Effect.gen(function* () {
      const repository = yield* ReviewRepository;
      const pairing = yield* PairingService;
      const bots = yield* DemoBots;
      const digest = yield* Digest.Digest;
      const random = yield* SecureRandom.SecureRandom;

      const hash = (code: ReviewCode) => digest.digestHex(Digest.sha256, encoder.encode(code));

      // The alphabet has 32 symbols, so masking a random byte to 5 bits picks one without bias.
      const newCode = Effect.map(random.randomBytes(reviewCodeLength), (bytes) =>
        decodeReviewCode(Array.from(bytes, (byte) => inviteCodeAlphabet[byte & 31]).join("")),
      );

      const pairOf = (userId: UserId) =>
        pairing.pair(userId).pipe(
          Effect.map(Option.some),
          Effect.catchTag("NotPaired", () => Effect.succeed(Option.none<PairResponse>())),
          Effect.mapError(unavailable("pairing-unavailable")),
        );

      // Stills the bot first, so it never acts in a pair that is being ended.
      const endPair = (pair: PairResponse, partner: UserId) =>
        bots
          .stop(pair.pairId)
          .pipe(
            Effect.mapError(unavailable("room-unavailable")),
            Effect.andThen(
              pairing.unpair(partner).pipe(Effect.mapError(unavailable("pairing-unavailable"))),
            ),
          );

      const claim = Effect.fn("ReviewService.claim")(function* (
        claimerId: UserId,
        code: ReviewCode,
      ): Effect.fn.Return<PairId, InvalidInvite | AlreadyPaired | ReviewUnavailable> {
        yield* annotateRefs({ user: claimerId });
        const now = yield* Clock.currentTimeMillis;
        const codeHash = yield* hash(code);
        const found = yield* repository.liveCode(codeHash, now);
        if (Option.isNone(found) || found.value === claimerId) return yield* new InvalidInvite();
        const partner = found.value;

        const mine = yield* pairOf(claimerId);
        if (Option.isSome(mine)) {
          // A reinstall signs back in to the same account, still in the review pair.
          if (mine.value.members[1] === partner) return mine.value.pairId;
          return yield* new AlreadyPaired();
        }
        const theirs = yield* pairOf(partner);
        if (Option.isSome(theirs)) yield* endPair(theirs.value, partner);

        const { code: invite } = yield* pairing.createInvite(partner).pipe(
          // Another claim paired the partner at the same moment.
          Effect.mapError(unavailable("pairing-raced")),
        );
        const pairId = yield* pairing
          .claimInvite(claimerId, invite)
          .pipe(
            Effect.catchTag("PairingUnavailable", (error) =>
              Effect.fail(unavailable("pairing-unavailable")(error)),
            ),
          );
        yield* annotateRefs({ pair: pairId });
        yield* repository.claimed(codeHash, now);
        // A bot that never wakes still leaves a partner to pair with, so this does not fail it.
        yield* bots
          .start(pairId, claimerId, partner)
          .pipe(Effect.catch((error) => Effect.logWarning("review bot not started", error)));
        return pairId;
      });

      const status = Effect.gen(function* () {
        const now = yield* Clock.currentTimeMillis;
        const partner = yield* repository.partner;
        const pair = Option.isSome(partner) ? yield* pairOf(partner.value) : Option.none();
        const codes = yield* repository.codes(20);
        return {
          partner: Option.getOrNull(partner),
          pairId: Option.isSome(pair) ? pair.value.pairId : null,
          codes: codes.map((code) => ({
            lastFour: code.lastFour,
            createdAt: code.createdAt,
            createdBy: code.createdBy,
            expiresAt: code.expiresAt,
            revokedAt: code.revokedAt,
            claims: code.claims,
            lastClaimedAt: code.lastClaimedAt,
            live: code.revokedAt === null && code.expiresAt > now,
          })),
          changes: yield* repository.changes(50),
        };
      }).pipe(Effect.withSpan("ReviewService.status"));

      const partnerOrOpen = Effect.gen(function* () {
        const found = yield* repository.partner;
        if (Option.isSome(found)) return found.value;
        const userId = decodeUserId(yield* random.uuidV4());
        yield* repository.createPartner({ userId, createdAt: yield* Clock.currentTimeMillis });
        return userId;
      });

      const issue = Effect.fn("ReviewService.issue")(function* (by: string, days: number) {
        const partnerId = yield* partnerOrOpen;
        const code = yield* newCode;
        const createdAt = yield* Clock.currentTimeMillis;
        const lifetime = Math.min(Math.max(Math.round(days), 1), reviewCodeMaxDays);
        const expiresAt = createdAt + Duration.toMillis(Duration.days(lifetime));
        const lastFour = code.slice(-4);
        yield* repository.issue({
          codeHash: yield* hash(code),
          partnerId,
          lastFour,
          createdAt,
          createdBy: by,
          expiresAt,
        });
        return { code, lastFour, expiresAt };
      });

      const record = (by: string, action: ReviewAction) =>
        Effect.flatMap(Clock.currentTimeMillis, (at) => repository.record({ at, by, action }));

      const revoke = Effect.fn("ReviewService.revoke")(function* (by: string) {
        yield* repository.revoke({ at: yield* Clock.currentTimeMillis, by });
      });

      const wipe = Effect.fn("ReviewService.wipe")(function* (by: string) {
        const partner = yield* repository.partner;
        if (Option.isSome(partner)) {
          const pair = yield* pairOf(partner.value);
          if (Option.isSome(pair)) yield* endPair(pair.value, partner.value);
        }
        yield* record(by, "wipe");
      });

      return ReviewService.of({ claim, status, issue, revoke, wipe });
    }),
  );
}
