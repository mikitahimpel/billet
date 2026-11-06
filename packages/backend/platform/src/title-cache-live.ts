import { Effect, Layer, Option } from "effect";
import { TitleCache } from "@billet/backend-titles/title-cache";
import { sha256Hex } from "./hashed-session-tokens.ts";
import { logLine } from "./observability.ts";

/** KV keeps nothing for less than this. */
const shortestTtlSeconds = 60;

// A key can hold what a caller searched for, so KV only sees its hash, which also keeps it under
// KV's 512-byte key limit.
const kvKey = async (key: string) => `titles:${await sha256Hex(key)}`;

/** `TitleCache` on the `TITLES` KV namespace. A KV failure is a miss, logged as a fixed label. */
export const TitleCacheLive = (kv: KVNamespace): Layer.Layer<TitleCache> =>
  Layer.succeed(
    TitleCache,
    TitleCache.of({
      get: (key) =>
        Effect.tryPromise(async () => kv.get(await kvKey(key))).pipe(
          Effect.map(Option.fromNullishOr),
          Effect.orElseSucceed(() => {
            logLine("warn", "title cache unavailable");
            return Option.none<string>();
          }),
        ),
      put: (key, value, ttlSeconds) =>
        Effect.tryPromise(async () =>
          kv.put(await kvKey(key), value, {
            expirationTtl: Math.max(shortestTtlSeconds, Math.ceil(ttlSeconds)),
          }),
        ).pipe(Effect.orElseSucceed(() => logLine("warn", "title cache unavailable"))),
    }),
  );
