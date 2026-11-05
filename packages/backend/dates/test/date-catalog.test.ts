import { describe, expect, it } from "vitest";
import { dateCatalog } from "../src/date-catalog.ts";
import raw from "../src/date-catalog.json" with { type: "json" };

describe("date catalogue", () => {
  it("has a version that matches its ideas", async () => {
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(JSON.stringify(raw.ideas)),
    );
    const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
    expect(raw.version, "run `pnpm --filter @billet/backend-dates catalog:version`").toBe(
      hex.slice(0, 16),
    );
  });

  it("gives every idea its own id", () => {
    const ids = dateCatalog.ideas.map((idea) => idea.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("gives every idea its own picture", () => {
    const paths = dateCatalog.ideas.map((idea) => idea.art.path);
    expect(new Set(paths).size).toBe(paths.length);
  });
});
