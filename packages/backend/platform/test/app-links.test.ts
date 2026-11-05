import { describe, expect, it } from "vitest";
import { appId, respondAppLink } from "../src/app-links.ts";

describe("Universal Links", () => {
  it("serves the association file for invite links", async () => {
    const response = respondAppLink("/.well-known/apple-app-site-association");
    expect(await response?.json()).toEqual({
      applinks: { details: [{ appIDs: [appId], components: [{ "/": "/i/*" }] }] },
    });
  });

  it("answers an invite link with a page, and leaves other paths alone", () => {
    expect(respondAppLink("/i/K7QM4R2XHP")?.status).toBe(200);
    expect(respondAppLink("/i/K7QM4R2XH0")).toBeUndefined();
    expect(respondAppLink("/i/K7QM4")).toBeUndefined();
    expect(respondAppLink("/")).toBeUndefined();
  });
});
