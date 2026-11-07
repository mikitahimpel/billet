import { Effect, Layer, Option } from "effect";
import { ShopArt } from "../src/shop-art.ts";

/** A `ShopArt` in memory. */
export const InMemoryShopArt = (): Layer.Layer<ShopArt> => {
  const files = new Map<string, Uint8Array>();
  return Layer.succeed(
    ShopArt,
    ShopArt.of({
      put: (key, bytes) => Effect.sync(() => void files.set(key, bytes)),
      get: (key) => Effect.sync(() => Option.fromNullishOr(files.get(key))),
    }),
  );
};
