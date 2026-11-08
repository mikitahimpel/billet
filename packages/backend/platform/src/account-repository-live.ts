import { Effect, Layer, Option, Schema } from "effect";
import { AccountUnavailable } from "@billet/backend-account/account-error";
import { AccountRepository } from "@billet/backend-account/account-repository";
import { AccountNotices } from "@billet/backend-auth/account-notices";
import { EpochMillis, UserId } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";
import { PartnerLeftReason } from "@billet/contracts-http-api/account";
import { spanMethods } from "@billet/backend-observability/span-methods";

/** What a `partner_notices` row holds. A test fails if the table's columns differ. */
export const StoredPartnerNotice = Schema.Struct({
  userId: UserId,
  reason: PartnerLeftReason,
  at: EpochMillis,
});

const decodePairIds = Schema.decodeUnknownEffect(Schema.Array(PairId));
const decodeNotice = Schema.decodeUnknownOption(
  Schema.Struct({ reason: PartnerLeftReason, at: EpochMillis }),
);

// A storage error can quote a bound value, so nothing from it survives this label.
const guarded = <A>(run: () => Promise<A>) =>
  Effect.tryPromise({
    try: run,
    catch: (cause) => new AccountUnavailable({ reason: "directory-unavailable", cause }),
  });

/**
 * `AccountRepository` on the D1 directory. The erase is one `batch`, which D1 runs as a single
 * transaction. Its order follows the foreign keys: rows that point at `users` without a cascade
 * go before it, and deleting `auth_user` takes its sessions and Apple link with it.
 */
export const AccountRepositoryLive = (db: D1Database): Layer.Layer<AccountRepository> =>
  Layer.succeed(
    AccountRepository,
    AccountRepository.of(
      spanMethods("AccountRepository", {
        pairsOf: (userId) =>
          guarded(() =>
            db
              .prepare(
                `SELECT pair_id FROM pair_members WHERE user_id = ?1
               UNION
               SELECT DISTINCT pair_id FROM pair_events WHERE user_id = ?1 AND pair_id != ''`,
              )
              .bind(userId)
              .all<{ pair_id: string }>(),
          ).pipe(
            Effect.flatMap(({ results }) => decodePairIds(results.map(({ pair_id }) => pair_id))),
            Effect.mapError(
              (cause) => new AccountUnavailable({ reason: "directory-unavailable", cause }),
            ),
          ),

        erase: ({ userId, partner, at }) =>
          guarded(() =>
            db.batch([
              ...Option.match(partner, {
                onNone: () => [],
                onSome: (partnerId) => [
                  db
                    .prepare(
                      `INSERT INTO partner_notices (user_id, reason, at) VALUES (?, 'account-deleted', ?)
                     ON CONFLICT (user_id) DO UPDATE SET reason = excluded.reason, at = excluded.at`,
                    )
                    .bind(partnerId, at),
                ],
              }),
              db
                .prepare(
                  `DELETE FROM pair_members WHERE pair_id IN
                   (SELECT pair_id FROM pair_members WHERE user_id = ?)`,
                )
                .bind(userId),
              db.prepare("DELETE FROM invites WHERE owner_id = ?").bind(userId),
              db.prepare("DELETE FROM kept_wallets WHERE user_id = ?").bind(userId),
              db.prepare("DELETE FROM kept_items WHERE user_id = ?").bind(userId),
              db
                .prepare("DELETE FROM blocks WHERE blocker_id = ?1 OR blocked_id = ?1")
                .bind(userId),
              db.prepare("DELETE FROM pair_events WHERE user_id = ?").bind(userId),
              db.prepare("DELETE FROM onboarding_answers WHERE user_id = ?").bind(userId),
              db.prepare("DELETE FROM auth_user WHERE id = ?").bind(userId),
              db.prepare("DELETE FROM devices WHERE user_id = ?").bind(userId),
              db.prepare("DELETE FROM users WHERE id = ?").bind(userId),
            ]),
          ).pipe(Effect.asVoid),
      }),
    ),
  );

/** `AccountNotices` on the D1 directory. A notice counts only while its user has no pair. */
export const AccountNoticesLive = (db: D1Database): Layer.Layer<AccountNotices> =>
  Layer.succeed(
    AccountNotices,
    spanMethods("AccountNotices", {
      partnerLeft: (userId) =>
        Effect.tryPromise(() =>
          db
            .prepare(
              `SELECT reason, at FROM partner_notices
             WHERE user_id = ? AND NOT EXISTS (SELECT 1 FROM pair_members WHERE user_id = partner_notices.user_id)`,
            )
            .bind(userId)
            .first(),
        ).pipe(
          Effect.map((row) => (row === null ? Option.none() : decodeNotice(row))),
          Effect.catchCause(() =>
            Effect.logWarning("partner notice unreadable").pipe(Effect.as(Option.none())),
          ),
        ),
    }),
  );
