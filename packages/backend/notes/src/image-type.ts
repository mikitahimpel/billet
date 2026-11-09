import type { MediaKey } from "@billet/contracts-domain/ids";

/** The image formats `POST /v1/media` stores: a rendered drawing is a PNG, a photo any of them. */
export type ImageType = "png" | "jpeg" | "heic";

const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const jpegSignature = [0xff, 0xd8, 0xff];

/** `ftyp`, the box an ISO-BMFF file opens with, at offset 4 after the box's size. */
const fileTypeBox = [0x66, 0x74, 0x79, 0x70];

/** HEIF brands a camera writes; some encoders write the generic `mif1` in place of `heic`. */
const heifBrands = new Set(["heic", "heix", "heim", "heis", "hevc", "hevx", "mif1"]);

const startsWith = (bytes: Uint8Array, signature: ReadonlyArray<number>, offset = 0) =>
  bytes.length >= offset + signature.length &&
  signature.every((byte, index) => bytes[offset + index] === byte);

const majorBrand = (bytes: Uint8Array) => String.fromCharCode(...bytes.subarray(8, 12));

/** The format these bytes declare by their signature, or `undefined` for anything else. */
export const detectImageType = (bytes: Uint8Array): ImageType | undefined => {
  if (startsWith(bytes, pngSignature)) return "png";
  if (startsWith(bytes, jpegSignature)) return "jpeg";
  if (startsWith(bytes, fileTypeBox, 4) && bytes.length >= 12 && heifBrands.has(majorBrand(bytes)))
    return "heic";
  return undefined;
};

const extensions: Record<ImageType, string> = { png: "png", jpeg: "jpg", heic: "heic" };

const contentTypes: Record<string, string> = {
  png: "image/png",
  jpg: "image/jpeg",
  heic: "image/heic",
};

export const extensionOf = (type: ImageType): string => extensions[type];

/** By the key's extension; anything else is served as bytes, never as something to render. */
export const contentTypeOf = (key: MediaKey): string => {
  const dot = key.lastIndexOf(".");
  return (dot === -1 ? undefined : contentTypes[key.slice(dot + 1)]) ?? "application/octet-stream";
};
