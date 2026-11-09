import { eq } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { DemoPartnerUnavailable } from "@billet/backend-demo-partner/demo-partner-error";
import { DemoPartnerRepository } from "@billet/backend-demo-partner/demo-partner-repository";
import { spanMethods } from "@billet/backend-observability/span-methods";
import { UserId } from "@billet/contracts-domain/ids";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { demoPartners, users } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const unavailable = (cause: unknown) =>
  new DemoPartnerUnavailable({ reason: "directory-unavailable", cause });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

const decodeBotIds = Schema.decodeUnknownEffect(Schema.Array(Schema.Struct({ botId: UserId })));

const makeDemoPartnerRepository = (db: DirectoryDatabase): DemoPartnerRepository["Service"] =>
  DemoPartnerRepository.of(
    spanMethods("DemoPartnerRepository", {
      create: ({ botId, ownerId, createdAt }) =>
        guarded(
          atomically(db, [
            db.insert(users).values({ id: botId, createdAt }),
            db.insert(demoPartners).values({ botId, ownerId, createdAt }),
          ]),
        ).pipe(Effect.asVoid),

      botOf: (ownerId) =>
        guarded(
          db
            .select({ botId: demoPartners.botId })
            .from(demoPartners)
            .where(eq(demoPartners.ownerId, ownerId))
            .pipe(Effect.flatMap(decodeBotIds)),
        ).pipe(Effect.map(([row]) => Option.fromNullishOr(row?.botId))),

      isBot: (userId) =>
        guarded(
          db
            .select({ botId: demoPartners.botId })
            .from(demoPartners)
            .where(eq(demoPartners.botId, userId))
            .pipe(Effect.flatMap(decodeBotIds)),
        ).pipe(Effect.map((rows) => rows.length > 0)),

      forget: (botId) =>
        guarded(db.delete(demoPartners).where(eq(demoPartners.botId, botId))).pipe(Effect.asVoid),
    }),
  );

/** Build it once per request, as `openDirectoryDatabase` asks. */
export const DemoPartnerRepositoryLive = (
  binding: D1Database,
): Layer.Layer<DemoPartnerRepository> =>
  Layer.effect(
    DemoPartnerRepository,
    Effect.map(openDirectoryDatabase(binding), makeDemoPartnerRepository),
  );
