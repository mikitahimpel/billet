import { sql } from "drizzle-orm";
import { Effect, Layer } from "effect";
import { dailyEarnCaps } from "@billet/contracts-domain/coins";
import { EconomyTap, economyChange } from "@billet/backend-pair-room/economy";
import { atomically, type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { economyDays, economyPairDays } from "./directory-schema.ts";

const flag = (capped: ReadonlyArray<string>, source: keyof typeof dailyEarnCaps) =>
  capped.includes(source) ? 1 : 0;

/**
 * Adds the change to its UTC day's source totals and to the pair's row for the day. Totals add;
 * the pair's balance is the one after its latest coin change, and a cap once reached stays reached
 * for the day.
 */
export const recordEconomy = (
  db: DirectoryDatabase,
  observation: Parameters<typeof economyChange>[0],
) => {
  const change = economyChange(observation);
  const day = change.day;
  const lastAt = observation.at;
  return atomically(db, [
    ...change.totals.map(({ source, credited, debited, entries }) =>
      db
        .insert(economyDays)
        .values({ day, source, credited, debited, entries })
        .onConflictDoUpdate({
          target: [economyDays.day, economyDays.source],
          set: {
            credited: sql`${economyDays.credited} + excluded.credited`,
            debited: sql`${economyDays.debited} + excluded.debited`,
            entries: sql`${economyDays.entries} + excluded.entries`,
          },
        }),
    ),
    db
      .insert(economyPairDays)
      .values({
        pairId: observation.pairId,
        day,
        earned: change.earned,
        balance: change.balance,
        lastAt,
        cappedCare: flag(change.capped, "care"),
        cappedNotes: flag(change.capped, "notes"),
        cappedGames: flag(change.capped, "games"),
        cappedLists: flag(change.capped, "lists"),
      })
      .onConflictDoUpdate({
        target: [economyPairDays.pairId, economyPairDays.day],
        set: {
          earned: sql`${economyPairDays.earned} + excluded.earned`,
          balance: sql`case when excluded.last_at >= ${economyPairDays.lastAt} then excluded.balance else ${economyPairDays.balance} end`,
          lastAt: sql`max(${economyPairDays.lastAt}, excluded.last_at)`,
          cappedCare: sql`max(${economyPairDays.cappedCare}, excluded.capped_care)`,
          cappedNotes: sql`max(${economyPairDays.cappedNotes}, excluded.capped_notes)`,
          cappedGames: sql`max(${economyPairDays.cappedGames}, excluded.capped_games)`,
          cappedLists: sql`max(${economyPairDays.cappedLists}, excluded.capped_lists)`,
        },
      }),
  ]);
};

/**
 * The economy's counters never delay or fail a coin change: the write runs on its own fibre and a
 * failure is one fixed log line.
 */
export const EconomyTapLive = (binding: D1Database): Layer.Layer<EconomyTap> =>
  Layer.succeed(EconomyTap, {
    observe: (observation) =>
      Effect.scoped(
        openDirectoryDatabase(binding).pipe(Effect.flatMap((db) => recordEconomy(db, observation))),
      ).pipe(
        Effect.catchCause(() => Effect.logWarning("economy counters not written")),
        Effect.forkDetach,
        Effect.asVoid,
      ),
  });
