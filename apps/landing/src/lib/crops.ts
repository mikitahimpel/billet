import { roomAsset } from "./room-assets";

// Close-ups of the room renders (src/assets/room/crop-<name>-{800,1400}.{avif,webp}), by the size of their box in
// the 2560×1440 render, which fixes their aspect. Sharper renders of the same boxes replace the files, not the names.
const boxes = {
  paw: [204, 330],
  shelf: [300, 290],
  candle: [325, 370],
  window: [350, 410],
  "window-lamp": [740, 460],
  bed: [610, 400],
  post: [410, 440],
  mochi: [330, 210],
} as const;

export type CropName = keyof typeof boxes;

export function crop(name: CropName) {
  const [width, height] = boxes[name];
  const set = (format: "avif" | "webp") =>
    [800, 1400].map((w) => `${roomAsset(`crop-${name}-${w}.${format}`)} ${w}w`).join(", ");
  return {
    avif: set("avif"),
    webp: set("webp"),
    src: roomAsset(`crop-${name}-800.webp`),
    width: 800,
    height: Math.round((800 * height) / width),
    aspect: 800 / Math.round((800 * height) / width),
  };
}
