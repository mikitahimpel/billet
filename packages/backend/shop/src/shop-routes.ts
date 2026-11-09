import { Effect, Layer, Option, Schema } from "effect";
import { Digest } from "effect/crypto";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { ShopPictureKey } from "@billet/contracts-domain/shop-catalog";
import { routes } from "@billet/contracts-http-api/routes";
import { ShopCatalogResponse } from "@billet/contracts-http-api/shop";
import { ShopArt, shopArtContentType, type ShopArtType } from "./shop-art.ts";
import { ShopStore } from "./shop-store.ts";

const encoder = new TextEncoder();
const encodeCatalog = Schema.encodeSync(ShopCatalogResponse);
const isPictureKey = Schema.is(ShopPictureKey);

/** `If-None-Match` is `*` or a comma-separated list of tags, each maybe weak (`W/"..."`). */
const matchesEtag = (ifNoneMatch: string | undefined, etag: string): boolean =>
  ifNoneMatch !== undefined &&
  ifNoneMatch
    .split(",")
    .map((tag) => tag.trim().replace(/^W\//, ""))
    .some((tag) => tag === "*" || tag === etag);

const unavailable = Effect.succeed(
  HttpServerResponse.text(JSON.stringify({ _tag: "Unavailable" }), {
    status: 503,
    contentType: "application/json",
  }),
);

/** No session: the same for everyone, so shared caches keep the catalog a minute. */
export const ShopCatalogRoutes = HttpRouter.use((router) =>
  Effect.gen(function* () {
    const store = yield* ShopStore;
    const art = yield* ShopArt;
    const digest = yield* Digest.Digest;

    yield* router.add(
      routes.getShopCatalog.method,
      routes.getShopCatalog.path,
      Effect.gen(function* () {
        const items = yield* store.active;
        const list = JSON.stringify(encodeCatalog({ version: "0000000000000000", items }).items);
        const version = (yield* digest
          .digestHex(Digest.sha256, encoder.encode(list))
          .pipe(Effect.orDie)).slice(0, 16);
        const etag = `"${version}"`;
        const headers = { "cache-control": "public, max-age=60", etag };
        const request = yield* HttpServerRequest.HttpServerRequest;
        if (matchesEtag(request.headers["if-none-match"], etag)) {
          return HttpServerResponse.empty({ status: 304, headers });
        }
        return HttpServerResponse.text(`{"version":"${version}","items":${list}}`, {
          contentType: "application/json",
          headers,
        });
      }).pipe(Effect.catchTag("ShopStoreUnavailable", () => unavailable)),
    );

    yield* router.add(
      routes.getShopArt.method,
      routes.getShopArt.path,
      Effect.gen(function* () {
        const request = yield* HttpServerRequest.HttpServerRequest;
        const key = new URL(request.url, "http://billet.invalid").pathname.split("/").pop() ?? "";
        if (!isPictureKey(key)) return HttpServerResponse.empty({ status: 404 });
        const found = yield* art.get(key);
        if (Option.isNone(found)) return HttpServerResponse.empty({ status: 404 });
        const type = key.split(".")[1] as ShopArtType;
        // The key is a hash of the bytes, so what it names never changes.
        return HttpServerResponse.uint8Array(found.value, {
          contentType: shopArtContentType[type],
          headers: { "cache-control": "public, max-age=31536000, immutable" },
        });
      }).pipe(Effect.catchTag("ShopArtUnavailable", () => unavailable)),
    );
  }),
).pipe(Layer.orDie);
