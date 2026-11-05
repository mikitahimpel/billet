// Transcodes the vendored splats to SPZ, keeping every splat in its order: the .skin files bind weights by index.
// Usage: node scripts/ply-to-spz.mjs src/scene/assets/cat-sit.ply …
import { readFile, writeFile } from "node:fs/promises";
import { transcodeSpz } from "@sparkjsdev/spark";

for (const path of process.argv.slice(2)) {
  const fileBytes = new Uint8Array(await readFile(path));
  const { fileBytes: spz, clippedCount } = await transcodeSpz({
    inputs: [{ fileBytes, pathOrUrl: path }],
    maxSh: 0,
  });
  const out = path.replace(/\.ply$/, ".spz");
  await writeFile(out, spz);
  console.log(`${path}: ${fileBytes.length} -> ${spz.length} bytes, clipped ${clippedCount}`);
}
