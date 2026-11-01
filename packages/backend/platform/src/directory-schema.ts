import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

// D1 tables. `Drizzle.Schema` in the root alchemy.run.ts generates migrations from this file, so it
// imports nothing but drizzle-orm: drizzle-kit loads it in Node, outside the Worker.
export const directoryProbe = sqliteTable("directory_probe", {
  id: text("id").primaryKey(),
  createdAt: integer("created_at").notNull(),
});
