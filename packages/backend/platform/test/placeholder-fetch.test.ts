import { describe, expect, it } from "vitest";
import { respondPlaceholder } from "../src/placeholder-fetch.ts";

describe("respondPlaceholder", () => {
  it("answers 200 with a small JSON body", async () => {
    const response = respondPlaceholder();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ service: "billet-api", status: "ok" });
  });
});
