import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { beforeEach, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { AuthRejected } from "@billet/backend-auth/auth-error";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { titlePath } from "@billet/contracts-http-api/routes";
import { TitleDetails, TitleSearchResponse } from "@billet/contracts-http-api/titles";
import { TitleCache } from "../src/title-cache.ts";
import { TitleCatalog } from "../src/title-catalog.ts";
import { TitleNotFound, TitlesBusy, TitlesUnavailable } from "../src/titles-error.ts";
import { TitlesRoutes } from "../src/titles-routes.ts";
import { Tmdb } from "../src/tmdb.ts";

const FakeAuth = Layer.succeed(
  AuthService,
  AuthService.of({
    issueChallenge: Effect.die("unused"),
    signInAnonymously: () => Effect.die("unused"),
    signInWithApple: () => Effect.die("unused"),
    linkApple: () => Effect.die("unused"),
    account: () => Effect.die("unused"),
    signOut: () => Effect.die("unused"),
    registerPushToken: () => Effect.die("unused"),
    authenticate: (token) =>
      Redacted.value(token) === "good"
        ? Effect.succeed({
            userId: Schema.decodeSync(UserId)("ana"),
            deviceId: Schema.decodeSync(DeviceId)("device"),
            sessionHash: "hash",
          } satisfies Principal)
        : Effect.fail(new AuthRejected({ reason: "session-unknown" })),
  }),
);

// TMDB's own shapes, nulls and people included.
const search = {
  page: 1,
  results: [
    {
      media_type: "movie",
      id: 329865,
      title: "Arrival",
      release_date: "2016-11-10",
      poster_path: "/evHCf9GuBDc42KvW9DRhY7pKx11.jpg",
      vote_average: 7.6,
      vote_count: 19000,
    },
    { media_type: "person", id: 1, name: "Amy Adams" },
    {
      media_type: "tv",
      id: 95396,
      name: "Severance",
      first_air_date: "2022-02-17",
      poster_path: null,
      vote_average: 0,
      vote_count: 0,
    },
    { media_type: "movie", id: 2, title: "", release_date: "" },
  ],
};
const arrival = {
  id: 329865,
  title: "Arrival",
  release_date: "2016-11-10",
  poster_path: "/evHCf9GuBDc42KvW9DRhY7pKx11.jpg",
  backdrop_path: "/yIZ1xendyqKvY3FGeeUYUd5X9Mm.jpg",
  overview: "A linguist talks with visitors.",
  genres: [
    { id: 18, name: "Drama" },
    { id: 878, name: "Science Fiction" },
  ],
  runtime: 116,
  vote_average: 7.6,
  vote_count: 19000,
  "watch/providers": {
    results: {
      PT: {
        link: "https://www.themoviedb.org/movie/329865/watch?locale=PT",
        flatrate: [{ provider_id: 8, provider_name: "Netflix", logo_path: "/netflix.jpg" }],
        rent: [{ provider_id: 2, provider_name: "Apple TV" }],
        buy: [
          { provider_id: 2, provider_name: "Apple TV" },
          { provider_id: 8, provider_name: "Netflix" },
        ],
      },
    },
  },
};
const severance = {
  id: 95396,
  name: "Severance",
  first_air_date: "2022-02-17",
  number_of_seasons: 2,
};

// Severance and an Arrival-like film for Arrival; Arrival, a new show and Severance again for Severance.
const recommended: Readonly<Record<string, unknown>> = {
  "/movie/329865/recommendations": {
    page: 1,
    results: [search.results[2], { ...search.results[0], id: 7 }],
  },
  "/tv/95396/recommendations": {
    page: 1,
    results: [
      { media_type: "movie", id: 329865, title: "Arrival" },
      { media_type: "tv", id: 8, name: "Silo" },
      search.results[2],
    ],
  },
};

interface Call {
  readonly path: string;
  readonly params: Readonly<Record<string, string>>;
}

let calls: Array<Call> = [];
let busyFor: number | undefined;

const FakeTmdb = Layer.succeed(
  Tmdb,
  Tmdb.of({
    get: (path, params) =>
      Effect.suspend((): Effect.Effect<string, TitleNotFound | TitlesBusy | TitlesUnavailable> => {
        calls.push({ path, params });
        if (busyFor !== undefined) {
          return Effect.fail(new TitlesBusy({ retryAfterSeconds: busyFor }));
        }
        const body =
          path === "/search/multi"
            ? search
            : path === "/movie/329865"
              ? arrival
              : path === "/tv/95396"
                ? severance
                : recommended[path];
        return body === undefined
          ? Effect.fail(new TitleNotFound())
          : Effect.succeed(JSON.stringify(body));
      }),
  }),
);

let handler: (request: Request) => Promise<Response>;

beforeEach(() => {
  calls = [];
  busyFor = undefined;
  const web = HttpRouter.toWebHandler(
    TitlesRoutes.pipe(
      Layer.provide(Layer.mergeAll(FakeAuth, TitleCatalog.layer)),
      Layer.provide(Layer.mergeAll(FakeTmdb, TitleCache.memory())),
    ),
    { disableLogger: true },
  );
  handler = (request) => web.handler(request);
  return web.dispose;
});

const get = (path: string, token = "good") =>
  handler(
    new Request(`http://billet.test${path}`, { headers: { authorization: `Bearer ${token}` } }),
  );
const searchFor = async (q: string) => {
  const response = await get(`/v1/titles/search?q=${encodeURIComponent(q)}`);
  expect(response.status).toBe(200);
  return Schema.decodeUnknownSync(TitleSearchResponse)(await response.json()).results;
};

describe("title search", () => {
  it("is proxied to TMDB, with films and shows only and each one's length", async () => {
    expect(await searchFor("  Arrival ")).toEqual([
      {
        kind: "movie",
        tmdb: 329865,
        title: "Arrival",
        year: 2016,
        posterPath: "/evHCf9GuBDc42KvW9DRhY7pKx11.jpg",
        rating: 7.6,
        runtime: 116,
      },
      { kind: "tv", tmdb: 95396, title: "Severance", year: 2022, seasons: 2 },
    ]);
    expect(calls[0]).toEqual({
      path: "/search/multi",
      params: { query: "arrival", language: "en", include_adult: "false", page: "1" },
    });
    expect(calls.map((call) => call.path).toSorted()).toEqual([
      "/movie/329865",
      "/search/multi",
      "/tv/95396",
    ]);
  });

  it("is cached: the same search, however typed, and the card after it ask TMDB nothing", async () => {
    const first = await searchFor("Arrival");
    const asked = calls.length;
    expect(await searchFor("arrival")).toEqual(first);
    expect((await get(titlePath("movie", 329865))).status).toBe(200);
    expect(calls).toHaveLength(asked);
  });

  it("honours a 429: answers it with Retry-After and asks TMDB nothing until then", async () => {
    await searchFor("Arrival");
    busyFor = 30;
    const busy = await get("/v1/titles/search?q=dune");
    expect(busy.status).toBe(429);
    expect(busy.headers.get("retry-after")).toBe("30");
    const asked = calls.length;

    const again = await get("/v1/titles/search?q=past%20lives");
    expect(again.status).toBe(429);
    expect(Number(again.headers.get("retry-after"))).toBeGreaterThan(28);
    expect(calls).toHaveLength(asked);

    // What is cached is still served.
    expect(await searchFor("Arrival")).toHaveLength(2);
    expect(calls).toHaveLength(asked);
  });

  it("needs a session and a query", async () => {
    expect((await get("/v1/titles/search?q=dune", "bad")).status).toBe(401);
    expect((await get("/v1/titles/search")).status).toBe(400);
    expect((await get(`/v1/titles/search?q=${"x".repeat(101)}`)).status).toBe(400);
    expect(calls).toEqual([]);
  });
});

describe("title details", () => {
  it("answers the card with where to watch in the caller's country", async () => {
    const response = await get(`${titlePath("movie", 329865)}?country=PT&lang=pt-PT`);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("private, max-age=86400");
    expect(Schema.decodeUnknownSync(TitleDetails)(await response.json())).toEqual({
      kind: "movie",
      tmdb: 329865,
      title: "Arrival",
      year: 2016,
      posterPath: "/evHCf9GuBDc42KvW9DRhY7pKx11.jpg",
      rating: 7.6,
      runtime: 116,
      backdropPath: "/yIZ1xendyqKvY3FGeeUYUd5X9Mm.jpg",
      overview: "A linguist talks with visitors.",
      genres: ["Drama", "Science Fiction"],
      watch: {
        country: "PT",
        link: "https://www.themoviedb.org/movie/329865/watch?locale=PT",
        stream: [{ id: 8, name: "Netflix", logoPath: "/netflix.jpg" }],
        rentOrBuy: [{ id: 2, name: "Apple TV" }],
      },
    });
    expect(calls).toEqual([
      {
        path: "/movie/329865",
        params: { language: "pt-PT", append_to_response: "watch/providers" },
      },
    ]);
  });

  it("answers no providers in a country TMDB has none for", async () => {
    const response = await get(`${titlePath("tv", 95396)}?country=SE`);
    const details = Schema.decodeUnknownSync(TitleDetails)(await response.json());
    expect(details.watch).toEqual({ country: "SE", stream: [], rentOrBuy: [] });
    expect(details.seasons).toBe(2);
  });

  it("answers 404 for a title TMDB lacks and 400 for a malformed one", async () => {
    expect((await get(titlePath("movie", 1))).status).toBe(404);
    expect((await get("/v1/titles/book/1")).status).toBe(400);
    expect((await get("/v1/titles/movie/0")).status).toBe(400);
    expect((await get("/v1/titles/movie/abc")).status).toBe(400);
  });
});

describe("title recommendations", () => {
  const recommend = async (ids: string) => {
    const response = await get(`/v1/titles/recommendations?ids=${ids}`);
    expect(response.status).toBe(200);
    return Schema.decodeUnknownSync(TitleSearchResponse)(await response.json()).results;
  };

  it("takes titles in turn from each seed's list, without repeats or the seeds", async () => {
    const found = await recommend("movie:329865,tv:95396");
    expect(found.map((title) => `${title.kind}:${title.tmdb}`)).toEqual(["movie:7", "tv:8"]);
    expect(calls.map((call) => call.path).toSorted()).toEqual([
      "/movie/329865/recommendations",
      "/tv/95396/recommendations",
    ]);
  });

  it("is cached, and a seed TMDB lacks adds nothing", async () => {
    await recommend("movie:329865");
    const asked = calls.length;
    await recommend("movie:329865");
    expect(calls).toHaveLength(asked);
    expect(await recommend("movie:1")).toEqual([]);
  });

  it("needs a session and 1 to 5 well-formed ids", async () => {
    expect((await get("/v1/titles/recommendations?ids=movie:1", "bad")).status).toBe(401);
    expect((await get("/v1/titles/recommendations")).status).toBe(400);
    expect((await get("/v1/titles/recommendations?ids=book:1")).status).toBe(400);
    const six = Array.from({ length: 6 }, (_, at) => `movie:${at + 1}`).join(",");
    expect((await get(`/v1/titles/recommendations?ids=${six}`)).status).toBe(400);
  });
});
