import { Context, Effect, Layer, Option } from "effect";

/** A failed read is a miss and a failed write a no-op: the cache never fails a request. */
export class TitleCache extends Context.Service<
  TitleCache,
  {
    readonly get: (key: string) => Effect.Effect<Option.Option<string>>;
    /** At least 60 seconds, the shortest KV keeps anything. */
    readonly put: (key: string, value: string, ttlSeconds: number) => Effect.Effect<void>;
  }
>()("@billet/backend-titles/TitleCache") {
  /** In memory, without expiry: one request's worth in tests and nothing else. */
  static readonly memory = (): Layer.Layer<TitleCache> => {
    const entries = new Map<string, string>();
    return Layer.succeed(
      TitleCache,
      TitleCache.of({
        get: (key) => Effect.sync(() => Option.fromNullishOr(entries.get(key))),
        put: (key, value) => Effect.sync(() => void entries.set(key, value)),
      }),
    );
  };
}
