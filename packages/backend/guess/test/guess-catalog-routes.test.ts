import { Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { GuessCatalogResponse } from "@billet/contracts-http-api/guess";
import { routes } from "@billet/contracts-http-api/routes";
import { GuessCatalogRoutes } from "../src/guess-catalog-routes.ts";
import { questionCatalog } from "../src/question-catalog.ts";

describe("question catalog route", () => {
  const { handler, dispose } = HttpRouter.toWebHandler(GuessCatalogRoutes, {
    disableLogger: true,
  });
  afterAll(() => dispose());

  const get = (headers: Record<string, string> = {}) =>
    handler(
      new Request(`http://billet.test${routes.getGuessCatalog.path}`, {
        method: routes.getGuessCatalog.method,
        headers,
      }),
    );

  it("answers the catalog without a session, cacheable, with its version as the ETag", async () => {
    const response = await get();
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("public, max-age=3600");
    expect(response.headers.get("etag")).toBe(`"${questionCatalog.version}"`);
    const body = Schema.decodeUnknownSync(GuessCatalogResponse)(await response.json());
    expect(body).toEqual(questionCatalog);
  });

  it("answers 304 with no body when the caller has this version", async () => {
    for (const tag of [
      `"${questionCatalog.version}"`,
      `W/"${questionCatalog.version}"`,
      `"old", "${questionCatalog.version}"`,
    ]) {
      const response = await get({ "if-none-match": tag });
      expect(response.status, tag).toBe(304);
      expect(await response.text()).toBe("");
    }
  });

  it("answers the catalog when the caller has another version", async () => {
    expect((await get({ "if-none-match": '"0000000000000000"' })).status).toBe(200);
  });
});
