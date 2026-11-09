import { desc, eq } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import { FunnelDefinition } from "@billet/backend-admin/admin-funnel";
import { FunnelStore, FunnelStoreUnavailable } from "@billet/backend-admin/funnel-store";
import { spanMethods } from "@billet/backend-observability/span-methods";
import { openDirectoryDatabase, type DirectoryDatabase } from "./directory-database.ts";
import { adminFunnels } from "./directory-schema.ts";

// A storage error can quote bound values, so nothing from it survives this label.
const guarded = <A, E>(effect: Effect.Effect<A, E>) =>
  Effect.mapError(
    effect,
    (cause) => new FunnelStoreUnavailable({ reason: "directory-unavailable", cause }),
  );

/** The definition is JSON text. */
export const FunnelRow = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  definition: Schema.String,
  createdAt: Schema.Int,
  createdBy: Schema.String,
});

const decodeRows = Schema.decodeUnknownEffect(Schema.Array(FunnelRow));
const decodeDefinition = Schema.decodeUnknownOption(Schema.fromJsonString(FunnelDefinition));

const makeFunnelStore = (db: DirectoryDatabase): FunnelStore["Service"] =>
  FunnelStore.of(
    spanMethods("FunnelStore", {
      // A saved definition that no longer decodes (an event name removed) is left out.
      all: guarded(
        db
          .select()
          .from(adminFunnels)
          .orderBy(desc(adminFunnels.createdAt))
          .pipe(Effect.flatMap(decodeRows)),
      ).pipe(
        Effect.map((rows) =>
          rows.flatMap((row) => {
            const definition = decodeDefinition(row.definition);
            return definition._tag === "Some" ? [{ ...row, definition: definition.value }] : [];
          }),
        ),
      ),
      save: (funnel) =>
        guarded(
          db
            .insert(adminFunnels)
            .values({ ...funnel, definition: JSON.stringify(funnel.definition) }),
        ).pipe(Effect.asVoid),
      remove: (id) =>
        guarded(
          db.delete(adminFunnels).where(eq(adminFunnels.id, id)).returning({ id: adminFunnels.id }),
        ).pipe(Effect.map((rows) => rows.length > 0)),
    }),
  );

/** Build it once per request, as `openDirectoryDatabase` asks. */
export const FunnelStoreLive = (binding: D1Database): Layer.Layer<FunnelStore> =>
  Layer.effect(FunnelStore, Effect.map(openDirectoryDatabase(binding), makeFunnelStore));
