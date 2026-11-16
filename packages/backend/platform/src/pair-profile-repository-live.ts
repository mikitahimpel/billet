import { and, eq, inArray, isNotNull, isNull } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { LocalDay } from "@billet/contracts-domain/coins";
import { UserId } from "@billet/contracts-domain/ids";
import { DisplayName } from "@billet/contracts-http-api/pair";
import { PairingUnavailable } from "@billet/backend-pairing/pairing-error";
import { PairProfileRepository } from "@billet/backend-pairing/pair-profile-repository";
import { spanMethods } from "@billet/backend-observability/span-methods";
import { type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { pairMembers, users } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const guarded = <A, E>(effect: Effect.Effect<A, E>) =>
  Effect.mapError(
    effect,
    (cause) => new PairingUnavailable({ reason: "directory-unavailable", cause }),
  );

const decodeNames = Schema.decodeUnknownEffect(
  Schema.Array(Schema.Struct({ userId: UserId, displayName: DisplayName })),
);
const decodeDays = Schema.decodeUnknownEffect(
  Schema.Array(Schema.Struct({ togetherSince: Schema.NullOr(LocalDay) })),
);

const makePairProfileRepository = (db: DirectoryDatabase): PairProfileRepository["Service"] =>
  spanMethods("PairProfileRepository", {
    setName: (userId, name) =>
      guarded(db.update(users).set({ displayName: name }).where(eq(users.id, userId))).pipe(
        Effect.asVoid,
      ),

    names: (members) =>
      members.length === 0
        ? Effect.succeed([])
        : guarded(
            db
              .select({ userId: users.id, displayName: users.displayName })
              .from(users)
              .where(and(inArray(users.id, [...members]), isNotNull(users.displayName)))
              .pipe(Effect.flatMap(decodeNames)),
          ).pipe(
            // In the order asked, so the caller stays first.
            Effect.map((rows) =>
              members.flatMap((userId) => rows.filter((row) => row.userId === userId)),
            ),
          ),

    // Every member row holds the pair's day, so it goes when the pair does.
    setTogetherSince: (pairId, day, ifUnset) =>
      guarded(
        db
          .update(pairMembers)
          .set({ togetherSince: day })
          .where(
            ifUnset
              ? and(eq(pairMembers.pairId, pairId), isNull(pairMembers.togetherSince))
              : eq(pairMembers.pairId, pairId),
          )
          .returning({ userId: pairMembers.userId }),
      ).pipe(Effect.map((rows) => rows.length > 0)),

    togetherSince: (pairId) =>
      guarded(
        db
          .select({ togetherSince: pairMembers.togetherSince })
          .from(pairMembers)
          .where(and(eq(pairMembers.pairId, pairId), isNotNull(pairMembers.togetherSince)))
          .limit(1)
          .pipe(Effect.flatMap(decodeDays)),
      ).pipe(Effect.map(([row]) => Option.fromNullishOr(row?.togetherSince))),
  });

/** Build it once per request, as `openDirectoryDatabase` asks. */
export const PairProfileRepositoryLive = (
  binding: D1Database,
): Layer.Layer<PairProfileRepository> =>
  Layer.effect(
    PairProfileRepository,
    Effect.map(openDirectoryDatabase(binding), makePairProfileRepository),
  );
