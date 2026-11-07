import { Context, Data, type Effect, type Option } from "effect";

export type ShopArtType = "webp" | "png" | "jpg";

/** The largest picture an upload may be. */
export const shopArtMaxBytes = 1_048_576;

const startsWith = (bytes: Uint8Array, prefix: ReadonlyArray<number>, at = 0) =>
  prefix.every((byte, index) => bytes[at + index] === byte);

/** What the bytes are, by their first bytes, or undefined for anything but WebP, PNG and JPEG. */
export const shopArtTypeOf = (bytes: Uint8Array): ShopArtType | undefined => {
  if (startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && startsWith(bytes, [0x57, 0x45, 0x42, 0x50], 8))
    return "webp";
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "png";
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return "jpg";
  return undefined;
};

export const shopArtContentType: Record<ShopArtType, string> = {
  webp: "image/webp",
  png: "image/png",
  jpg: "image/jpeg",
};

/** The store could not be read or written. `reason` is a fixed label. */
export class ShopArtUnavailable extends Data.TaggedError("ShopArtUnavailable")<{
  readonly reason: string;
  readonly cause?: unknown;
}> {}

/** Pictures the admin uploaded for shop items, by content-hashed key. Never deleted. */
export class ShopArt extends Context.Service<
  ShopArt,
  {
    readonly put: (
      key: string,
      bytes: Uint8Array,
      contentType: string,
    ) => Effect.Effect<void, ShopArtUnavailable>;
    readonly get: (key: string) => Effect.Effect<Option.Option<Uint8Array>, ShopArtUnavailable>;
  }
>()("@billet/backend-shop/ShopArt") {}
