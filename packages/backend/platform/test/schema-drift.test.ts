import {
  StoredChallenge,
  StoredDevice,
  StoredPushToken,
  StoredSession,
  StoredUser,
} from "@billet/backend-auth/auth-repository";
import { StoredInvite, StoredPairMember } from "@billet/backend-pairing/pairing-repository";
import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";
import { describe, expect, it } from "vitest";
import * as directorySchema from "../src/directory-schema.ts";
import {
  authChallenges,
  devices,
  invites,
  pairMembers,
  pushTokens,
  rateLimits,
  sessions,
  users,
} from "../src/directory-schema.ts";
import { StoredRateLimit } from "../src/rate-limit.ts";
import { SampleRow, StoredNote, StoredRoom } from "../src/room-rows.ts";
import * as roomSchema from "../src/room-schema.ts";
import { note, room } from "../src/room-schema.ts";
import { domainShape, tableShape } from "./schema-drift.ts";
import { getTableName, tablesOf } from "./table-columns.ts";

// `drizzle-orm/effect-schema` derives from tables, while the domain is hand-written with brands and
// tagged unions, so neither can generate the other. Every exported table needs its domain type here: the test below
// fails on one that is missing.
const checked = [
  ["auth_challenges", authChallenges, StoredChallenge],
  ["devices", devices, StoredDevice],
  ["invites", invites, StoredInvite],
  ["pair_members", pairMembers, StoredPairMember],
  ["push_tokens", pushTokens, StoredPushToken],
  ["rate_limits", rateLimits, StoredRateLimit],
  ["note", note, StoredNote],
  ["room", room, StoredRoom],
  ["sessions", sessions, StoredSession],
  ["users", users, StoredUser],
] as const;

describe("tables match their Effect Schema", () => {
  it.each(checked)("%s", (_, table, domain) => {
    expect(tableShape(table)).toEqual(domainShape(domain));
  });

  it("covers every table the schema modules export", () => {
    const exported = [...tablesOf(directorySchema), ...tablesOf(roomSchema)].map(getTableName);
    expect(exported.length).toBeGreaterThan(0);
    expect(checked.map(([name]) => name).toSorted()).toEqual(exported.toSorted());
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
    expect(tableShape(table)).not.toEqual(domainShape(SampleRow));
  });
});
