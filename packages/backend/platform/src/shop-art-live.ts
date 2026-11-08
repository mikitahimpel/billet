import { Effect, Layer, Option } from "effect";
import { ShopArt, ShopArtUnavailable } from "@billet/backend-shop/shop-art";
import { spanMethods } from "@billet/backend-observability/span-methods";

// A storage error can quote the key, so nothing from it survives this label.
const guarded = <A>(run: () => Promise<A>) =>
  Effect.tryPromise({
    try: run,
    catch: (cause) => new ShopArtUnavailable({ reason: "art-unavailable", cause }),
  });

/** Keeps shop pictures under their own prefix in the media bucket, apart from the couples' notes. */
export const shopArtPrefix = "shop-art/";

/** `ShopArt` on the private R2 bucket; the Worker serves the pictures itself. */
export const ShopArtLive = (bucket: R2Bucket): Layer.Layer<ShopArt> =>
  Layer.succeed(
    ShopArt,
    ShopArt.of(
      spanMethods("ShopArt", {
        put: (key, bytes, contentType) =>
          guarded(() =>
            bucket.put(`${shopArtPrefix}${key}`, bytes, { httpMetadata: { contentType } }),
          ).pipe(Effect.asVoid),
        get: (key) =>
          guarded(async () => {
            const object = await bucket.get(`${shopArtPrefix}${key}`);
            return object === null
              ? Option.none<Uint8Array>()
              : Option.some(new Uint8Array(await object.arrayBuffer()));
          }),
      }),
    ),
  );
