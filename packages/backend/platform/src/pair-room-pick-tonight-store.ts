import { gte, lt } from "drizzle-orm";
import { Effect, Layer, Option, Schema } from "effect";
import { PickRow, PickTonightStore, pickKeyOf } from "@billet/backend-pair-room/pick-tonight";
import { PickTitle } from "@billet/contracts-domain/pick-tonight";
import { RoomDb } from "./pair-room-sqlite-store.ts";
import { movieSwipes } from "./room-schema.ts";

const decodeRow = Schema.decodeUnknownOption(PickRow);
const decodeTitle = Schema.decodeUnknownOption(PickTitle);

/** The card a stored key names; `item:<id>`, `movie:<tmdb>` or `tv:<tmdb>`. */
const titleOf = (key: string) => {
  const [kind, id] = key.split(":");
  return kind === "item"
    ? decodeTitle({ _tag: "Item", item: id })
    : decodeTitle({ _tag: "Title", kind, tmdb: Number(id) });
};

/** A row this code cannot read, such as one a newer build wrote, is left out. */
const rowFrom = (row: typeof movieSwipes.$inferSelect) =>
  Option.flatMap(titleOf(row.title), (title) =>
    decodeRow({
      member: row.member,
      title,
      choice: row.choice,
      name: row.name,
      ...(row.posterPath === null ? {} : { posterPath: row.posterPath }),
      at: row.at,
    }),
  );

export const SqlitePickTonightStore = Layer.effect(
  PickTonightStore,
  Effect.gen(function* () {
    const db = yield* RoomDb;
    return PickTonightStore.of({
      since: (since) =>
        db
          .select()
          .from(movieSwipes)
          .where(gte(movieSwipes.at, since))
          .pipe(
            Effect.map((rows) => rows.flatMap((row) => Option.toArray(rowFrom(row)))),
            Effect.orDie,
          ),
      put: (row, pruneBefore) => {
        const values = {
          member: row.member,
          title: pickKeyOf(row.title),
          choice: row.choice,
          name: row.name,
          posterPath: row.posterPath ?? null,
          at: row.at,
        };
        return db
          .transaction((tx) =>
            Effect.gen(function* () {
              yield* tx.delete(movieSwipes).where(lt(movieSwipes.at, pruneBefore));
              yield* tx
                .insert(movieSwipes)
                .values(values)
                .onConflictDoUpdate({
                  target: [movieSwipes.member, movieSwipes.title],
                  set: values,
                });
            }),
          )
          .pipe(Effect.asVoid, Effect.orDie);
      },
      forget: db.delete(movieSwipes).pipe(Effect.asVoid, Effect.orDie),
    });
  }),
);
