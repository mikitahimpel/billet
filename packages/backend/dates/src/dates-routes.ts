import { Effect, Schema } from "effect";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { DateCatalogResponse } from "@billet/contracts-http-api/dates";
import { routes } from "@billet/contracts-http-api/routes";
import { dateCatalog } from "./date-catalog.ts";

const etag = `"${dateCatalog.version}"`;
const body = JSON.stringify(Schema.encodeSync(DateCatalogResponse)(dateCatalog));
// The same for every caller and changed only by a deploy, so shared caches may keep it for an hour.
const headers = { "cache-control": "public, max-age=3600", etag };

/** `If-None-Match` is `*` or a comma-separated list of tags, each maybe weak (`W/"..."`). */
const matchesEtag = (ifNoneMatch: string | undefined): boolean =>
  ifNoneMatch !== undefined &&
  ifNoneMatch
    .split(",")
    .map((tag) => tag.trim().replace(/^W\//, ""))
    .some((tag) => tag === "*" || tag === etag);

/** The date catalogue route of the API. No session: the catalogue is public. */
export const DatesRoutes = HttpRouter.use((router) =>
  router.add(
    routes.getDateCatalog.method,
    routes.getDateCatalog.path,
    Effect.gen(function* () {
      const request = yield* HttpServerRequest.HttpServerRequest;
      return matchesEtag(request.headers["if-none-match"])
        ? HttpServerResponse.empty({ status: 304, headers })
        : HttpServerResponse.text(body, { contentType: "application/json", headers });
    }),
  ),
);
