import { Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterAll, describe, expect, it } from "vitest";
import { DateCatalogResponse } from "@billet/contracts-http-api/dates";
import { routes } from "@billet/contracts-http-api/routes";
import { dateCatalog } from "../src/date-catalog.ts";
import { DatesRoutes } from "../src/dates-routes.ts";

describe("date catalogue route", () => {
  const { handler, dispose } = HttpRouter.toWebHandler(DatesRoutes, {
    disableLogger: true,
  });
  afterAll(() => dispose());

  const get = (headers: Record<string, string> = {}) =>
    handler(
      new Request(`http://billet.test${routes.getDateCatalog.path}`, {
        method: routes.getDateCatalog.method,
        headers,
      }),
    );

  it("answers the catalogue without a session, cacheable, with its version as the ETag", async () => {
    const response = await get();
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("public, max-age=3600");
    expect(response.headers.get("etag")).toBe(`"${dateCatalog.version}"`);
    const body = Schema.decodeUnknownSync(DateCatalogResponse)(await response.json());
    expect(body).toEqual(dateCatalog);
    expect(body.ideas).toHaveLength(150);
  });

  it("answers 304 with no body when the caller has this version", async () => {
    for (const tag of [
      `"${dateCatalog.version}"`,
      `W/"${dateCatalog.version}"`,
      `"old", "${dateCatalog.version}"`,
    ]) {
      const response = await get({ "if-none-match": tag });
      expect(response.status, tag).toBe(304);
      expect(response.headers.get("etag")).toBe(`"${dateCatalog.version}"`);
      expect(await response.text()).toBe("");
    }
  });

  it("answers the catalogue when the caller has another version", async () => {
    expect((await get({ "if-none-match": '"0000000000000000"' })).status).toBe(200);
  });
});
