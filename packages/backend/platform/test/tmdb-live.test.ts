import { env } from "cloudflare:workers";
import { Effect, Layer, Redacted, Schema } from "effect";
import { HttpRouter } from "effect/http";
import { afterEach, describe, expect, it } from "vitest";
import { AuthService, type Principal } from "@billet/backend-auth/auth-service";
import { TitleCatalog } from "@billet/backend-titles/title-catalog";
import { TitlesRoutes } from "@billet/backend-titles/titles-routes";
import { Tmdb } from "@billet/backend-titles/tmdb";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";
import { titlePath } from "@billet/contracts-http-api/routes";
import { TitleSearchResponse } from "@billet/contracts-http-api/titles";
import { TitleCacheLive } from "../src/title-cache-live.ts";
import { TmdbLive, tmdbFor } from "../src/tmdb-live.ts";

const token = "eyJ-secret-tmdb-read-token";

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
    authenticate: (bearer) =>
      Effect.succeed({
        userId: Schema.decodeSync(UserId)(Redacted.value(bearer)),
        deviceId: Schema.decodeSync(DeviceId)("device"),
        sessionHash: "hash",
      } satisfies Principal),
  }),
);

interface Sent {
  readonly url: string;
  readonly authorization: string | null;
}

/** TMDB as `fetch` sees it: every request is kept, and each answer echoes what it was sent. */
const fakeTmdb = (answer: (url: URL) => Response) => {
  const sent: Array<Sent> = [];
  const fetcher = async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : input);
    sent.push({ url: url.href, authorization: new Headers(init?.headers).get("authorization") });
    return answer(url);
  };
  return { sent, fetcher: fetcher as typeof fetch };
};

const searchBody = (url: URL) =>
  JSON.stringify({
    results: [
      {
        media_type: "movie",
        id: 329865,
        title: "Arrival",
        release_date: "2016-11-10",
        // TMDB never sends these, but an answer that did must not reach the phone.
        api_key: token,
        echo: url.href,
      },
    ],
  });

const serve = (fetcher: typeof fetch) => {
  const { handler, dispose } = HttpRouter.toWebHandler(
    TitlesRoutes.pipe(
      Layer.provide(Layer.mergeAll(FakeAuth, TitleCatalog.layer)),
      Layer.provide(Layer.mergeAll(TmdbLive(token, fetcher), TitleCacheLive(env.TITLES))),
    ),
    { disableLogger: true },
  );
  disposers.push(dispose);
  return (path: string) =>
    handler(
      new Request(`https://billet.test${path}`, { headers: { authorization: "Bearer ana" } }),
    );
};

const disposers: Array<() => Promise<void>> = [];
const clearTitles = async () => {
  const { keys } = await env.TITLES.list();
  await Promise.all(keys.map(({ name }) => env.TITLES.delete(name)));
};
afterEach(async () => {
  await Promise.all(disposers.splice(0).map((dispose) => dispose()));
  await clearTitles();
});

const textOf = async (response: Response) =>
  [...response.headers].map(([name, value]) => `${name}: ${value}`).join("\n") +
  (await response.text());

describe("TMDB through the Worker", () => {
  it("signs each request in a header, never in the URL", async () => {
    const tmdb = fakeTmdb((url) => new Response(searchBody(url)));
    const get = serve(tmdb.fetcher);
    expect((await get("/v1/titles/search?q=Arrival&lang=pt-PT")).status).toBe(200);
    expect(tmdb.sent[0]).toEqual({
      url: "https://api.themoviedb.org/3/search/multi?query=arrival&language=pt-PT&include_adult=false&page=1",
      authorization: `Bearer ${token}`,
    });
    for (const { url } of tmdb.sent) expect(url).not.toContain(token);
  });

  it("never answers the key, whatever TMDB sends back", async () => {
    const answers = [
      (url: URL) => new Response(searchBody(url)),
      () =>
        new Response(JSON.stringify({ status_message: `Invalid key ${token}` }), { status: 401 }),
      () => new Response(`slow down ${token}`, { status: 429, headers: { "retry-after": "5" } }),
      () => new Response(`<html>${token}</html>`, { status: 500 }),
    ];
    for (const [index, answer] of answers.entries()) {
      const get = serve(fakeTmdb(answer).fetcher);
      const responses = [
        await get(`/v1/titles/search?q=case${index}`),
        await get(`${titlePath("movie", 329865 + index)}?country=PT`),
      ];
      for (const response of responses) expect(await textOf(response)).not.toContain(token);
      // A 429 pauses TMDB for every later case.
      await clearTitles();
    }
  });

  it("keeps answers in KV under a hash of the request", async () => {
    const tmdb = fakeTmdb((url) =>
      url.pathname === "/3/search/multi"
        ? new Response(searchBody(url))
        : new Response(JSON.stringify({ id: 329865, title: "Arrival", runtime: 116 })),
    );
    const first = await serve(tmdb.fetcher)("/v1/titles/search?q=Arrival");
    const results = Schema.decodeUnknownSync(TitleSearchResponse)(await first.json()).results;
    expect(results).toEqual([
      { kind: "movie", tmdb: 329865, title: "Arrival", year: 2016, runtime: 116 },
    ]);
    const asked = tmdb.sent.length;

    // Another Worker, the same KV.
    expect((await serve(tmdb.fetcher)("/v1/titles/search?q=arrival")).status).toBe(200);
    expect(tmdb.sent).toHaveLength(asked);
    const { keys } = await env.TITLES.list();
    expect(keys.length).toBeGreaterThan(0);
    for (const { name } of keys) expect(name).toMatch(/^titles:[0-9a-f]{64}$/);
  });

  it("answers TMDB's 429 with its Retry-After and stops asking", async () => {
    const tmdb = fakeTmdb(() => new Response("", { status: 429, headers: { "retry-after": "7" } }));
    const get = serve(tmdb.fetcher);
    const busy = await get("/v1/titles/search?q=dune");
    expect(busy.status).toBe(429);
    expect(busy.headers.get("retry-after")).toBe("7");
    expect((await serve(tmdb.fetcher)("/v1/titles/search?q=anora")).status).toBe(429);
    expect(tmdb.sent).toHaveLength(1);
  });
});

describe("tmdbFor", () => {
  const ask = (layer: Layer.Layer<Tmdb>) =>
    Effect.runPromise(
      Effect.gen(function* () {
        return yield* (yield* Tmdb).get("/search/multi", { query: "arrival" });
      }).pipe(Effect.provide(layer), Effect.result),
    );

  it("answers from the built-in titles without a token, except on prod", async () => {
    const local = await ask(tmdbFor(undefined, undefined));
    expect(local._tag).toBe("Success");
    expect(JSON.stringify(local)).toContain("Arrival");
    const prod = await ask(tmdbFor("", "prod"));
    expect(prod._tag).toBe("Failure");
  });
});
