import type { DBAdapter, DBTransactionAdapter, Where } from "better-auth/adapters";

const sessionModels = new Set(["session", "auth_session"]);

export const sha256Hex = async (text: string): Promise<string> =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)))]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

const hashValue = async (value: Where["value"]): Promise<Where["value"]> => {
  if (typeof value === "string") return sha256Hex(value);
  if (Array.isArray(value) && value.every((item) => typeof item === "string")) {
    return Promise.all(value.map(sha256Hex));
  }
  return value;
};

const hashWhere = (where: ReadonlyArray<Where> | undefined) =>
  where === undefined
    ? undefined
    : Promise.all(
        where.map(async (clause) =>
          clause.field === "token" ? { ...clause, value: await hashValue(clause.value) } : clause,
        ),
      );

/** The raw token the caller looked a session up by, if it named exactly one. */
const lookedUpToken = (where: ReadonlyArray<Where> | undefined): string | undefined => {
  const clause = where?.find(({ field }) => field === "token");
  return clause !== undefined &&
    (clause.operator === undefined || clause.operator === "eq") &&
    typeof clause.value === "string"
    ? clause.value
    : undefined;
};

const withToken = <T>(row: T, token: string | undefined): T =>
  row !== null && typeof row === "object" && token !== undefined ? { ...row, token } : row;

/**
 * Better Auth keeps session tokens as they are. This keeps their SHA-256 instead, as the API always
 * has: anyone who reads the table can't use what they read. Every lookup by token hashes the value
 * first, and a session found by its token comes back carrying that token, so Better Auth can still
 * hand it to the client. A session listed any other way carries only the hash. Plain SHA-256 is
 * enough: a token is at least 190 random bits, so there is nothing to guess.
 */
export const hashSessionTokens = (adapter: DBAdapter): DBAdapter => ({
  ...hashInside(adapter),
  // Better Auth runs some writes through the adapter it is handed here, so that one hashes too.
  transaction: (run) => adapter.transaction((inner) => run(hashInside(inner))),
});

const hashInside = (adapter: DBTransactionAdapter): DBTransactionAdapter => {
  const isSession = (model: string) => sessionModels.has(model);
  return {
    ...adapter,
    create: async (input) => {
      if (!isSession(input.model)) return adapter.create(input);
      const data: Record<string, unknown> = input.data;
      const token = typeof data["token"] === "string" ? data["token"] : undefined;
      const stored = token === undefined ? data : { ...data, token: await sha256Hex(token) };
      return withToken(
        await adapter.create({ ...input, data: stored as typeof input.data }),
        token,
      );
    },
    findOne: async (input) => {
      if (!isSession(input.model)) return adapter.findOne(input);
      const where = (await hashWhere(input.where)) ?? [];
      return withToken(await adapter.findOne({ ...input, where }), lookedUpToken(input.where));
    },
    findMany: async (input) => {
      if (!isSession(input.model)) return adapter.findMany(input);
      const where = await hashWhere(input.where);
      return adapter.findMany(where === undefined ? input : { ...input, where });
    },
    count: async (input) => {
      if (!isSession(input.model)) return adapter.count(input);
      const where = await hashWhere(input.where);
      return adapter.count(where === undefined ? input : { ...input, where });
    },
    update: async <T>(input: Parameters<DBTransactionAdapter["update"]>[0]) => {
      if (!isSession(input.model)) return adapter.update(input);
      const where = (await hashWhere(input.where)) ?? [];
      const token: unknown = input.update["token"];
      const update =
        typeof token === "string"
          ? { ...input.update, token: await sha256Hex(token) }
          : input.update;
      const row = await adapter.update<T>({ ...input, where, update });
      return withToken(row, typeof token === "string" ? token : lookedUpToken(input.where));
    },
    updateMany: async (input) => {
      if (!isSession(input.model)) return adapter.updateMany(input);
      return adapter.updateMany({ ...input, where: (await hashWhere(input.where)) ?? [] });
    },
    delete: async (input) => {
      if (!isSession(input.model)) return adapter.delete(input);
      return adapter.delete({ ...input, where: (await hashWhere(input.where)) ?? [] });
    },
    deleteMany: async (input) => {
      if (!isSession(input.model)) return adapter.deleteMany(input);
      return adapter.deleteMany({ ...input, where: (await hashWhere(input.where)) ?? [] });
    },
    consumeOne: async (input) => {
      if (!isSession(input.model)) return adapter.consumeOne(input);
      const where = (await hashWhere(input.where)) ?? [];
      return withToken(await adapter.consumeOne({ ...input, where }), lookedUpToken(input.where));
    },
  };
};
