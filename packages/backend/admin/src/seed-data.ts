import type { MetricEventName } from "@billet/contracts-domain/metrics";
import { addDays } from "@billet/backend-metrics/funnel";

/**
 * Made-up pairs for the admin panel, across ten weeks: who paired when, which variant they got,
 * which build and system they ran, and what they did each day. Deterministic: the same seed and
 * day give the same rows, so a test can check a view against a hand-written SQL query over them.
 *
 * Every id starts with `seed-`, so the rows can be told apart from real ones and removed
 * (`seedCleanupSql`). Nothing here is a person: no name, no note, no Apple subject.
 */

export interface SeedOptions {
  /** The last UTC day to make events for (`YYYY-MM-DD`). */
  readonly today: string;
  /** How many weeks of pairs, oldest first. Ten by default. */
  readonly weeks?: number;
  /** The PRNG seed. */
  readonly seed?: number;
  /** Scales the number of pairs formed each week. 1 makes about 170 pairs over ten weeks. */
  readonly scale?: number;
}

export interface SeedUser {
  readonly id: string;
  readonly createdAt: number;
}

export interface SeedMember {
  readonly userId: string;
  readonly pairId: string;
  readonly createdAt: number;
}

export interface SeedFlag {
  readonly pairId: string;
  readonly experimentKey: string;
  readonly variant: string;
  readonly assignedAt: number;
}

export interface SeedEvent {
  readonly pairId: string;
  readonly userId: string;
  readonly name: MetricEventName;
  readonly day: string;
  readonly count: number;
  readonly firstAt: number;
  readonly lastAt: number;
  /** `<marketing>+<build>`, as `x-billet-app-version` sends it; null for what the server records. */
  readonly appVersion: string | null;
  /** As `x-billet-os` sends it, such as `iOS 26.1`; null for what the server records. */
  readonly os: string | null;
}

export interface SeedDetail {
  readonly name: string;
  readonly detail: string;
  readonly day: string;
  readonly count: number;
  readonly total: number;
}

export interface Seed {
  readonly users: ReadonlyArray<SeedUser>;
  readonly members: ReadonlyArray<SeedMember>;
  readonly flags: ReadonlyArray<SeedFlag>;
  readonly events: ReadonlyArray<SeedEvent>;
  readonly details: ReadonlyArray<SeedDetail>;
}

/** The experiment the seed splits pairs by. A registry key, so the Experiments page lists it. */
export const seedExperiment = {
  key: "home-layout",
  variants: ["classic", "immersive"],
} as const;

/** Builds by the day they shipped; a person moves to a new one a few days after it ships. */
const builds: ReadonlyArray<{ readonly version: string; readonly week: number }> = [
  { version: "1.0.0+10", week: 0 },
  { version: "1.1.0+12", week: 3 },
  { version: "1.2.0+14", week: 6 },
  { version: "1.3.0+17", week: 9 },
];

const systems: ReadonlyArray<readonly [string, number]> = [
  ["iOS 26.1", 0.45],
  ["iOS 26.0", 0.25],
  ["iOS 18.6", 0.2],
  ["iOS 17.7", 0.1],
];

const cats = ["ginger", "tuxedo", "calico", "grey-tabby", "black", "siamese"];
const items = [
  "lamp-moon",
  "rug-round",
  "plant-monstera",
  "shelf-books",
  "bed-cloud",
  "poster-sea",
];
const toys = ["yarn", "feather-wand", "laser"];
const tricks = ["sit", "high-five", "spin"];

/** mulberry32: small, fast and the same everywhere. */
const random = (seed: number) => {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296;
  };
};

const serverNames: ReadonlySet<MetricEventName> = new Set([
  "InviteCreated",
  "PairClaimed",
  "NoteSent",
]);

const dayMillis = 86_400_000;
const startOf = (day: string) => Date.parse(`${day}T00:00:00Z`);
const pad = (n: number) => String(n).padStart(4, "0");

/**
 * Makes the rows. About 170 pairs (at `scale` 1) form over the weeks, more each week as the app
 * grows, plus inviters who never pair. Each pair has a pull (how much it uses the app) and a day it
 * drifts off; `immersive` pairs hold on a little longer but open the app less often, so the
 * experiment has a result and a guardrail to find.
 */
export const makeSeed = (options: SeedOptions): Seed => {
  const weeks = options.weeks ?? 10;
  const next = random(options.seed ?? 20_261_104);
  const scale = options.scale ?? 1;
  const today = options.today;
  const first = addDays(today, -weeks * 7 + 1);

  const users: Array<SeedUser> = [];
  const members: Array<SeedMember> = [];
  const flags: Array<SeedFlag> = [];
  const events = new Map<string, SeedEvent>();
  const details = new Map<string, SeedDetail>();

  const pick = <A>(list: ReadonlyArray<A>): A => list[Math.floor(next() * list.length)] as A;
  const chance = (p: number) => next() < p;
  const between = (low: number, high: number) => low + Math.floor(next() * (high - low + 1));
  const weighted = (list: ReadonlyArray<readonly [string, number]>) => {
    let roll = next();
    for (const [value, weight] of list) {
      roll -= weight;
      if (roll < 0) return value;
    }
    return list[0]?.[0] ?? "unknown";
  };
  /** The build a person runs on a day: the newest that shipped at least `lag` days before. */
  const buildOn = (day: string, lag: number) => {
    const week = Math.floor((startOf(day) - startOf(first)) / dayMillis / 7 - lag / 7);
    return builds.filter((build) => build.week <= week).at(-1)?.version ?? builds[0]!.version;
  };

  const record = (
    event: Omit<SeedEvent, "firstAt" | "lastAt" | "count"> & { readonly count?: number },
    at: number,
  ) => {
    const key = `${event.pairId}|${event.userId}|${event.name}|${event.day}`;
    const before = events.get(key);
    const count = event.count ?? 1;
    // The server records these itself, without the app's headers (`docs/experiments.md`).
    const fromServer = serverNames.has(event.name);
    const appVersion = fromServer ? null : event.appVersion;
    const os = fromServer ? null : event.os;
    events.set(
      key,
      before === undefined
        ? { ...event, appVersion, os, count, firstAt: at, lastAt: at }
        : {
            ...before,
            count: before.count + count,
            firstAt: Math.min(before.firstAt, at),
            lastAt: Math.max(before.lastAt, at),
            appVersion,
            os,
          },
    );
  };
  const detail = (name: string, value: string, day: string, total = 0) => {
    const key = `${name}|${value}|${day}`;
    const before = details.get(key);
    details.set(key, {
      name,
      detail: value,
      day,
      count: (before?.count ?? 0) + 1,
      total: (before?.total ?? 0) + total,
    });
  };

  let userNumber = 0;
  let pairNumber = 0;
  const newUser = (at: number) => {
    userNumber += 1;
    const user = { id: `seed-u-${pad(userNumber)}`, createdAt: at };
    users.push(user);
    return user;
  };

  for (let week = 0; week < weeks; week += 1) {
    // Growth: about 9 new pairs in the first week, about 25 in the last.
    const formed = Math.round((9 + (16 * week) / Math.max(1, weeks - 1)) * scale);
    // About one inviter in five never pairs.
    const lonely = Math.round(formed / 4);

    for (let index = 0; index < lonely; index += 1) {
      const day = addDays(first, week * 7 + between(0, 6));
      if (day > today) continue;
      const at = startOf(day) + between(8, 22) * 3_600_000;
      const user = newUser(at);
      const os = weighted(systems);
      const appVersion = buildOn(day, between(0, 6));
      record({ pairId: "", userId: user.id, name: "InviteCreated", day, appVersion, os }, at);
      record({ pairId: "", userId: user.id, name: "AppOpened", day, appVersion, os }, at - 60_000);
    }

    for (let index = 0; index < formed; index += 1) {
      const formedDay = addDays(first, week * 7 + between(0, 6));
      if (formedDay > today) continue;
      pairNumber += 1;
      const pairId = `seed-p-${pad(pairNumber)}`;
      const formedAt = startOf(formedDay) + between(7, 23) * 3_600_000 + between(0, 59) * 60_000;
      const variant = chance(0.5) ? "classic" : "immersive";
      const boost = variant === "immersive" ? 1.12 : 1;
      // How much this pair uses the app, and the day it drifts off.
      const pull = Math.min(0.95, (0.35 + next() * 0.6) * boost);
      // About one pair in seven settles in and never drifts off.
      const driftDay = chance(0.15 * boost)
        ? Number.POSITIVE_INFINITY
        : Math.round(-Math.log(1 - next()) * 20 * boost);

      const inviter = newUser(formedAt - between(1, 48) * 3_600_000);
      const partner = newUser(formedAt - between(0, 30) * 60_000);
      const people = [inviter, partner].map((user) => ({
        user,
        os: weighted(systems),
        lag: between(0, 10),
        widget: chance(0.6),
        widgetDay: between(0, 4),
        // Each partner's own pull, around the pair's.
        pull: Math.min(0.97, Math.max(0.1, pull + (next() - 0.5) * 0.25)),
      }));

      const inviteDay = new Date(inviter.createdAt).toISOString().slice(0, 10);
      const inviterVersion = buildOn(inviteDay, people[0]!.lag);
      record(
        {
          pairId: "",
          userId: inviter.id,
          name: "InviteCreated",
          day: inviteDay,
          appVersion: inviterVersion,
          os: people[0]!.os,
        },
        inviter.createdAt + 60_000,
      );
      for (const { user } of people) members.push({ userId: user.id, pairId, createdAt: formedAt });
      flags.push({ pairId, experimentKey: seedExperiment.key, variant, assignedAt: formedAt });

      for (let offset = 0; addDays(formedDay, offset) <= today; offset += 1) {
        const day = addDays(formedDay, offset);
        const drifted = offset > driftDay;
        for (const person of people) {
          const { user, os } = person;
          const appVersion = buildOn(day, person.lag);
          const base = { pairId, userId: user.id, day, appVersion, os };
          const at = (hour: number) =>
            Math.max(offset === 0 ? formedAt : 0, startOf(day) + hour * 3_600_000) +
            between(0, 59) * 60_000;

          if (offset === 0) {
            record({ ...base, name: "AppOpened" }, formedAt - 120_000);
            record({ ...base, name: "PairClaimed" }, formedAt);
          }
          const pActive = drifted ? person.pull * 0.12 : person.pull * (offset === 0 ? 1 : 0.92);
          if (offset > 0 && !chance(pActive)) continue;

          // Immersive pairs stay longer each time and open the app less: a guardrail to catch.
          const opens = between(1, drifted ? 1 : variant === "immersive" ? 2 : 4);
          record({ ...base, name: "AppOpened", count: opens }, at(between(7, 22)));
          if (chance(drifted ? 0.3 : 0.55 + person.pull * 0.4)) {
            record({ ...base, name: "NoteSent", count: between(1, 3) }, at(between(8, 23)));
            if (chance(0.5)) record({ ...base, name: "NoteOpened" }, at(between(8, 23)));
            if (chance(0.5)) detail("NoteOpened", person.widget ? "widget" : "app", day);
          }
          if (person.widget && offset === person.widgetDay) {
            record({ ...base, name: "WidgetAdded" }, at(between(9, 22)));
            detail("WidgetAdded", pick(["small", "medium"]), day);
          }
          const product = (name: MetricEventName, p: number, max = 1, value?: string) => {
            if (!chance(p)) return;
            record({ ...base, name, count: between(1, max) }, at(between(7, 23)));
            if (value !== undefined) detail(name, value, day);
          };
          if (offset === 0) product("CatChosen", 0.9, 1, pick(cats));
          product("CatPetted", 0.75, 8);
          if (chance(0.5)) {
            record({ ...base, name: "CatFed" }, at(between(7, 23)));
            detail("CatFed", chance(0.8) ? "treat" : "food", day);
          }
          product("CatPlayed", 0.3, 3, pick(toys));
          product("CatCalled", 0.2, 2);
          if (offset >= 7) product("TrickDone", 0.15, 2, pick(tricks));
          product("StreakOpened", 0.15);
          if (offset === 3 || offset === 7 || offset === 14 || offset === 30) {
            product("StreakMilestoneSeen", 0.6, 1, `streak-${offset}`);
          }
          if (person.widget && offset >= person.widgetDay) {
            if (chance(0.3)) {
              record({ ...base, name: "WidgetButtonTapped" }, at(between(7, 23)));
              detail("WidgetButtonTapped", chance(0.7) ? "pet" : "treat", day);
            }
          }
          if (chance(variant === "immersive" ? 0.14 : 0.1)) {
            record({ ...base, name: "DecoratingOpened" }, at(between(7, 23)));
            product("RoomItemPlaced", 0.7, 2, pick(items));
            product("RoomItemMoved", 0.4, 3, pick(items));
          }
          if (chance(0.18)) {
            record({ ...base, name: "ShopOpened" }, at(between(7, 23)));
            product("ShopItemViewed", 0.8, 4, pick(items));
            if (chance(0.25)) {
              const price = pick([40, 60, 90, 120]);
              record({ ...base, name: "ShopItemBought" }, at(between(7, 23)));
              detail("ShopItemBought", pick(items), day, price);
            }
            if (chance(0.3)) {
              record({ ...base, name: "ShopDailyGiftClaimed" }, at(between(7, 23)));
              detail("ShopDailyGiftClaimed", "stamps", day, 10);
            }
          }
          product("ProfileOpened", 0.05);
        }
      }
    }
  }

  return {
    users,
    members,
    flags,
    events: [...events.values()].toSorted(
      (a, b) =>
        a.day.localeCompare(b.day) ||
        a.pairId.localeCompare(b.pairId) ||
        a.userId.localeCompare(b.userId) ||
        a.name.localeCompare(b.name),
    ),
    details: [...details.values()].toSorted(
      (a, b) =>
        a.day.localeCompare(b.day) ||
        a.name.localeCompare(b.name) ||
        a.detail.localeCompare(b.detail),
    ),
  };
};

const quote = (value: string | number | null) =>
  value === null
    ? "NULL"
    : typeof value === "number"
      ? String(value)
      : `'${value.replaceAll("'", "''")}'`;

const insert = (
  table: string,
  columns: ReadonlyArray<string>,
  rows: ReadonlyArray<ReadonlyArray<string | number | null>>,
  conflict: string,
): ReadonlyArray<string> => {
  const out: Array<string> = [];
  // D1 caps a statement's size; 100 rows a statement stays far below it.
  for (let start = 0; start < rows.length; start += 100) {
    const values = rows
      .slice(start, start + 100)
      .map((row) => `(${row.map(quote).join(", ")})`)
      .join(",\n  ");
    out.push(`INSERT INTO ${table} (${columns.join(", ")}) VALUES\n  ${values}\n${conflict};`);
  }
  return out;
};

/** Removes every seeded row that can be told apart (all but `event_details`, which has no owner). */
export const seedCleanupSql = [
  "DELETE FROM pair_flags WHERE pair_id LIKE 'seed-%';",
  "DELETE FROM pair_events WHERE user_id LIKE 'seed-%';",
  "DELETE FROM pair_members WHERE user_id LIKE 'seed-%';",
  "DELETE FROM users WHERE id LIKE 'seed-%';",
] as const;

/**
 * The seed as SQL statements for D1, each well under D1's statement limit: the cleanup first (so
 * running it twice gives the same rows), then the inserts. `event_details` rows add to what is
 * there, since they cannot be told apart.
 */
export const seedStatements = (
  seed: Seed,
  columns: { readonly eventBuild: boolean },
): ReadonlyArray<string> => [
  ...seedCleanupSql,
  ...insert(
    "users",
    ["id", "created_at"],
    seed.users.map((user) => [user.id, user.createdAt]),
    "ON CONFLICT DO NOTHING",
  ),
  ...insert(
    "pair_members",
    ["user_id", "pair_id", "created_at"],
    seed.members.map((member) => [member.userId, member.pairId, member.createdAt]),
    "ON CONFLICT DO NOTHING",
  ),
  ...insert(
    "pair_flags",
    ["pair_id", "experiment_key", "variant", "assigned_at"],
    seed.flags.map((flag) => [flag.pairId, flag.experimentKey, flag.variant, flag.assignedAt]),
    "ON CONFLICT DO NOTHING",
  ),
  ...insert(
    "pair_events",
    [
      "pair_id",
      "user_id",
      "name",
      "day",
      "count",
      "first_at",
      "last_at",
      ...(columns.eventBuild ? ["app_version", "os"] : []),
    ],
    seed.events.map((event) => [
      event.pairId,
      event.userId,
      event.name,
      event.day,
      event.count,
      event.firstAt,
      event.lastAt,
      ...(columns.eventBuild ? [event.appVersion, event.os] : []),
    ]),
    "ON CONFLICT DO NOTHING",
  ),
  ...insert(
    "event_details",
    ["name", "detail", "day", "count", "total"],
    seed.details.map((row) => [row.name, row.detail, row.day, row.count, row.total]),
    "ON CONFLICT (name, detail, day) DO UPDATE SET count = count + excluded.count, total = total + excluded.total",
  ),
];

/** `seedStatements` as one file, for `wrangler d1 execute --file`. */
export const seedSql = (seed: Seed, columns: { readonly eventBuild: boolean }): string =>
  seedStatements(seed, columns).join("\n");
