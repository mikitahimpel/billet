import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

// Durable Object SQLite tables, one set per `PairRoom`. `pnpm db:generate` writes the migrations.
export const roomProbe = sqliteTable("room_probe", {
  id: text("id").primaryKey(),
  createdAt: integer("created_at").notNull(),
});
