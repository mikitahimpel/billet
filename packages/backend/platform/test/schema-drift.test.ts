import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";
import { describe, expect, it } from "vitest";
import { directoryProbe } from "../src/directory-schema.ts";
import { PlatformProbe } from "../src/platform-probe.ts";
import { roomProbe } from "../src/room-schema.ts";
import { domainShape, tableShape } from "./schema-drift.ts";

// `drizzle-orm/effect-schema` derives from tables, while the domain is hand-written with brands and
// tagged unions, so neither can generate the other. Add every table here with its domain type.
describe("tables match their Effect Schema", () => {
  it.each([
    ["directory_probe", directoryProbe],
    ["room_probe", roomProbe],
  ])("%s", (_, table) => {
    expect(tableShape(table)).toEqual(domainShape(PlatformProbe));
  });

  it.each([
    [
      "a renamed column",
      sqliteTable("t", { id: text("id").primaryKey(), created: integer("c").notNull() }),
    ],
    [
      "a changed type",
      sqliteTable("t", { id: text("id").primaryKey(), createdAt: text("c").notNull() }),
    ],
    [
      "a nullable column",
      sqliteTable("t", { id: text("id").primaryKey(), createdAt: integer("c") }),
    ],
    [
      "an extra column",
      sqliteTable("t", {
        id: text("id").primaryKey(),
        createdAt: integer("c").notNull(),
        extra: text("e").notNull(),
      }),
    ],
  ])("catches %s", (_, table) => {
    expect(tableShape(table)).not.toEqual(domainShape(PlatformProbe));
  });
});
